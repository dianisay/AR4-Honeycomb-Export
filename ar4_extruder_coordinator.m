% ar4_extruder_coordinator.m
% =========================================================================
% Coordinador: lee la trayectoria del honeycomb y genera los comandos
% sincronizados de movimiento (AR4) + extrusion (Syringe Pump ESP32).
%
% Logica:
%   - Recorre el CSV punto por punto
%   - Cuando Tipo cambia de 0->1 (inicio de deposicion):
%       envia POST /extrude al ESP32 con el volumen del segmento
%   - Cuando Tipo cambia de 1->0 (fin de deposicion):
%       la extrusion ya termino (es por volumen, no por tiempo)
%   - En cada punto: envia las coordenadas XYZ al AR4 (via Monse)
%
% SALIDA:
%   - ar4_commands.csv: secuencia de comandos para el AR4 + extrusor
%     Formato: X, Y, Z, Ori, Tipo, ExtrudeCmd, VolumenML
%       ExtrudeCmd: 0 = nada, 1 = iniciar extrusion, 2 = reload
%       VolumenML: volumen a extruir (solo cuando ExtrudeCmd=1)
%
%   - Comunicacion directa con el ESP32 (si LIVE_MODE = true)
%
% REQUISITOS:
%   - Primero ejecutar export_honeycomb_for_ar4.m para generar los CSV
%   - ESP32 del extrusor conectado a la misma red WiFi
% =========================================================================

close all; clear; clc;

%% =================== CONFIGURACION ===================

% --- Archivo de trayectoria ---
TRAJ_FILE = 'ar4_honeycomb_paredes.csv';  % o 'ar4_honeycomb_completo.csv'

% --- Parametros del extrusor ---
BEAD_DIAMETER  = 0.8;    % mm — diametro del filete de material
BEAD_AREA      = pi * (BEAD_DIAMETER/2)^2;  % mm^2 — area transversal

% --- Conexion al ESP32 ---
ESP32_IP   = '192.168.1.100';  % ← CAMBIAR a la IP real del ESP32
LIVE_MODE  = false;            % true = enviar comandos HTTP al ESP32
                                % false = solo generar la tabla de comandos

% --- Volumen minimo para enviar comando (evitar micro-extrusions) ---
VOL_MIN_ML = 0.01;  % mL

%% =================== 1. CARGAR TRAYECTORIA ===================
if ~isfile(TRAJ_FILE)
    error(['No se encontro %s.\n' ...
           'Ejecuta export_honeycomb_for_ar4.m primero.'], TRAJ_FILE);
end

data = readmatrix(TRAJ_FILE);
% Columnas: X, Y, Z, Orientacion, Tipo
X   = data(:,1);
Y   = data(:,2);
Z   = data(:,3);
ORI = data(:,4);
TIPO = data(:,5);  % 0 = travel, 1 = deposition

N = size(data, 1);
fprintf('Trayectoria cargada: %d puntos desde %s\n', N, TRAJ_FILE);
fprintf('  Puntos de deposicion: %d (%.1f%%)\n', sum(TIPO==1), 100*sum(TIPO==1)/N);
fprintf('  Puntos de viaje:      %d (%.1f%%)\n', sum(TIPO==0), 100*sum(TIPO==0)/N);

%% =================== 2. IDENTIFICAR SEGMENTOS ===================
% Un "segmento de deposicion" es un bloque continuo de puntos con Tipo=1.
% Para cada segmento calculamos la longitud del recorrido y el volumen.

segments = [];  % cada fila: [idx_inicio, idx_fin, longitud_mm, volumen_mL]
in_segment = false;
seg_start = 0;

for i = 1:N
    if TIPO(i) == 1 && ~in_segment
        in_segment = true;
        seg_start = i;
    elseif TIPO(i) == 0 && in_segment
        in_segment = false;
        seg_end = i - 1;

        path_len = 0;
        for k = seg_start:seg_end-1
            dx = X(k+1) - X(k);
            dy = Y(k+1) - Y(k);
            dz = Z(k+1) - Z(k);
            path_len = path_len + sqrt(dx^2 + dy^2 + dz^2);
        end

        vol_mm3 = BEAD_AREA * path_len;  % mm^3
        vol_mL  = vol_mm3 / 1000;        % 1 mL = 1000 mm^3

        segments = [segments; seg_start, seg_end, path_len, vol_mL]; %#ok
    end
end

% Cerrar ultimo segmento si la trayectoria termina depositando
if in_segment
    seg_end = N;
    path_len = 0;
    for k = seg_start:seg_end-1
        dx = X(k+1) - X(k);
        dy = Y(k+1) - Y(k);
        dz = Z(k+1) - Z(k);
        path_len = path_len + sqrt(dx^2 + dy^2 + dz^2);
    end
    vol_mm3 = BEAD_AREA * path_len;
    vol_mL  = vol_mm3 / 1000;
    segments = [segments; seg_start, seg_end, path_len, vol_mL]; %#ok
end

n_seg = size(segments, 1);
vol_total = sum(segments(:,4));

fprintf('\nSegmentos de deposicion encontrados: %d\n', n_seg);
fprintf('  Volumen total estimado: %.3f mL\n', vol_total);
fprintf('\n  Seg  Inicio    Fin  Longitud(mm)  Volumen(mL)\n');
for s = 1:n_seg
    fprintf('  %3d  %6d  %6d  %10.1f    %8.4f\n', ...
        s, segments(s,1), segments(s,2), segments(s,3), segments(s,4));
end

%% =================== 3. GENERAR TABLA DE COMANDOS ===================
% Agregar columnas: ExtrudeCmd (0=nada, 1=extruir, 2=reload) y VolumenML

ExtrudeCmd = zeros(N, 1);
VolumenML  = zeros(N, 1);

for s = 1:n_seg
    idx = segments(s, 1);  % primer punto del segmento
    vol = segments(s, 4);

    if vol >= VOL_MIN_ML
        ExtrudeCmd(idx) = 1;   % comando: iniciar extrusion
        VolumenML(idx)  = vol;  % volumen a extruir
    end
end

% Tabla completa: X, Y, Z, Ori, Tipo, ExtrudeCmd, VolumenML
commands = [X, Y, Z, ORI, TIPO, ExtrudeCmd, VolumenML];

%% =================== 4. EXPORTAR CSV DE COMANDOS ===================
writematrix(commands, 'ar4_commands.csv');

fprintf('\n============================================\n');
fprintf(' ar4_commands.csv generado (%d puntos)\n', N);
fprintf('============================================\n');
fprintf(' Columnas: X, Y, Z, Ori, Tipo, ExtrudeCmd, VolumenML\n');
fprintf('   ExtrudeCmd: 0=nada, 1=extruir, 2=reload\n');
fprintf('   VolumenML:  volumen en mL (solo cuando ExtrudeCmd=1)\n');
fprintf('\n Preview (puntos con comando de extrusion):\n');
fprintf('  Punto    X        Y        Z     Ori  Tipo  Cmd   Vol(mL)\n');

cmd_rows = find(ExtrudeCmd > 0);
for r = 1:min(20, numel(cmd_rows))
    i = cmd_rows(r);
    fprintf('  %5d  %7.2f  %7.2f  %7.2f  %3.0f   %d     %d    %.4f\n', ...
        i, commands(i,:));
end
if numel(cmd_rows) > 20
    fprintf('  ... (%d comandos mas)\n', numel(cmd_rows) - 20);
end

%% =================== 5. MODO LIVE (ESP32) ===================
if LIVE_MODE
    fprintf('\n=== MODO LIVE: Conectando al ESP32 en %s ===\n', ESP32_IP);
    base_url = sprintf('http://%s', ESP32_IP);

    % Verificar conexion
    try
        status = webread(sprintf('%s/status', base_url));
        fprintf('  ESP32 conectado. Estado: %s, Angulo: %.1f°\n', ...
            status.estado, status.angulo_actual);
    catch err
        error('No se pudo conectar al ESP32 en %s: %s', ESP32_IP, err.message);
    end

    % Preguntar antes de iniciar
    fprintf('\n  Volumen total a extruir: %.3f mL\n', vol_total);
    fprintf('  Segmentos: %d\n', n_seg);
    resp = input('  Iniciar secuencia? (s/n): ', 's');
    if ~strcmpi(resp, 's')
        fprintf('  Cancelado.\n');
        return;
    end

    % Ejecutar secuencia
    opts = weboptions('MediaType', 'application/json', 'Timeout', 10);

    for i = 1:N
        % --- Aqui es donde Monse envia XYZ al AR4 ---
        % robot_move(X(i), Y(i), Z(i), ORI(i));  % ← funcion de Monse

        % --- Comando de extrusion ---
        if ExtrudeCmd(i) == 1
            vol = VolumenML(i);
            fprintf('  [Punto %d] EXTRUIR %.4f mL\n', i, vol);

            try
                body = struct('volume_ml', vol);
                result = webwrite(sprintf('%s/extrude', base_url), body, opts);
                fprintf('    -> OK: angulo %.1f° -> %.1f°\n', ...
                    result.angulo_inicio, result.angulo_objetivo);
            catch err
                warning('Error en /extrude en punto %d: %s', i, err.message);

                % Si el embolo esta lleno, hacer reload automatico
                if contains(err.message, 'ANGULO_MAX') || contains(err.message, '409')
                    fprintf('    -> Embolo lleno. Ejecutando /reload...\n');
                    try
                        webwrite(sprintf('%s/reload', base_url), struct(), opts);
                        pause(6);  % esperar retraccion completa
                        webwrite(sprintf('%s/extrude', base_url), body, opts);
                        fprintf('    -> Reload + reintento OK\n');
                    catch err2
                        warning('Error en reload+reintento: %s', err2.message);
                    end
                end
            end
        end

        % Pausa entre puntos (ajustar segun velocidad del AR4)
        % pause(0.05);
    end

    fprintf('\n  Secuencia completada.\n');

    % Status final
    try
        status = webread(sprintf('%s/status', base_url));
        fprintf('  Estado final ESP32: %s, Angulo: %.1f°\n', ...
            status.estado, status.angulo_actual);
    catch
    end
else
    fprintf('\n(LIVE_MODE = false — solo se genero ar4_commands.csv)\n');
    fprintf('Para enviar comandos al ESP32, cambiar LIVE_MODE = true\n');
    fprintf('y configurar ESP32_IP con la IP del extrusor.\n');
end

%% =================== 6. VISUALIZACION ===================
figure('Name','Coordinacion Trayectoria + Extrusion','Position',[50 50 1400 550]);

% Panel 1: Trayectoria con segmentos de deposicion coloreados
subplot(1,3,1);
hold on;
travel_mask = TIPO == 0;
dep_mask    = TIPO == 1;
plot3(X(travel_mask), Y(travel_mask), Z(travel_mask), '.', ...
    'Color', [0.7 0.7 0.7], 'MarkerSize', 2);
plot3(X(dep_mask), Y(dep_mask), Z(dep_mask), 'b.', 'MarkerSize', 3);

% Marcar inicio de cada extrusion
ext_pts = find(ExtrudeCmd == 1);
plot3(X(ext_pts), Y(ext_pts), Z(ext_pts), 'rv', ...
    'MarkerSize', 8, 'MarkerFaceColor', 'r');
xlabel('X (mm)'); ylabel('Y (mm)'); zlabel('Z (mm)');
title('Trayectoria (rojo = inicio extrusion)');
legend('Viaje', 'Deposicion', 'Cmd Extruir', 'Location', 'best');
grid on; axis equal; view(135, 25);

% Panel 2: Volumen por segmento
subplot(1,3,2);
bar(1:n_seg, segments(:,4), 'FaceColor', [0.2 0.6 0.3]);
xlabel('Segmento'); ylabel('Volumen (mL)');
title(sprintf('Volumen por segmento (total: %.3f mL)', vol_total));
grid on;

% Panel 3: Timeline de comandos
subplot(1,3,3);
hold on;
plot(1:N, TIPO, 'b-', 'LineWidth', 0.5);
stem(ext_pts, ones(size(ext_pts)) * 1.5, 'r', 'filled', 'MarkerSize', 4);
xlabel('Punto'); ylabel('Tipo / Comando');
title('Timeline: deposicion (azul) y comandos extrusion (rojo)');
yticks([0 1 1.5]);
yticklabels({'Viaje', 'Deposicion', 'Cmd Extruir'});
ylim([-0.2 2]);
grid on;

sgtitle('Coordinacion AR4 + Extrusor ESP32', 'FontSize', 13, 'FontWeight', 'bold');
