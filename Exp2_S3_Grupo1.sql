
-- ==============================================================================================
--  INTEGRANTES:                SEBÁSTIAN OLAVE - LILIANA TAPIA
-- ==============================================================================================

--***********************************************************************************************
--                                       CASO 1
--***********************************************************************************************

-------------------------------------------------------------------------------------------------
-- 1) Declarar la variable bind
-------------------------------------------------------------------------------------------------
VARIABLE b_anio_acreditacion NUMBER;

-------------------------------------------------------------------------------------------------
-- 2) Asignar un valor a la variable bind 
-------------------------------------------------------------------------------------------------
BEGIN
    :b_anio_acreditacion := EXTRACT(YEAR FROM SYSDATE);
END;
/

DECLARE
    --------------------------------------------------------------------------------------------
    -- [1] Para el año de acreditación desde la variable bind
    --------------------------------------------------------------------------------------------
    v_anio_acreditacion NUMBER := :b_anio_acreditacion;

    --------------------------------------------------------------------------------------------
    -- [2] Definición de VARRAY con multas por día de atraso
    --------------------------------------------------------------------------------------------
    TYPE MultaArray IS VARRAY(7) OF NUMBER;
    v_multas MultaArray := MultaArray(1200, 1300, 1700, 1900, 1100, 2000, 2300);

    ------------------------------------------------------------------------------
    -- [3] Cursor para obtener atenciones pagadas fuera de plazo (año anterior)
    ------------------------------------------------------------------------------
    CURSOR c_morosos IS
        SELECT a.ATE_ID,
               a.PAC_RUN,
               p.DV_RUN,
               p.PNOMBRE,
               p.SNOMBRE,
               p.APATERNO,
               p.AMATERNO,
               a.ESP_ID,
               pa.FECHA_VENC_PAGO,
               pa.FECHA_PAGO,
               (pa.FECHA_PAGO - pa.FECHA_VENC_PAGO) AS DIAS_MOROSIDAD,
               p.FECHA_NACIMIENTO
          FROM ATENCION a
          JOIN PAGO_ATENCION pa ON a.ATE_ID = pa.ATE_ID
          JOIN PACIENTE p ON a.PAC_RUN = p.PAC_RUN
         WHERE EXTRACT(YEAR FROM pa.FECHA_PAGO) = v_anio_acreditacion - 1
           AND pa.FECHA_PAGO > pa.FECHA_VENC_PAGO
         ORDER BY pa.FECHA_VENC_PAGO ASC, p.APATERNO ASC;

    ------------------------------------------------------------------------------
    -- [4] Declaración estática de variables 
    ------------------------------------------------------------------------------
    -- Campos a leer desde el cursor
    v_ate_id          NUMBER(10);
    v_pac_run         NUMBER(10);
    v_dv_run          VARCHAR2(1);
    v_pnombre         VARCHAR2(50);
    v_snombre         VARCHAR2(50);
    v_apaterno        VARCHAR2(50);
    v_amaterno        VARCHAR2(50);
    v_esp_id          NUMBER(5);
    v_fecha_venc_pago DATE;
    v_fecha_pago      DATE;
    v_dias_morosidad  NUMBER(8,2);
    v_fecha_nacimiento DATE;

    -- Variables adicionales para cálculo
    v_multa_total         NUMBER(10,2);
    v_descuento           NUMBER(5,2) := 0;
    v_nombre_especialidad VARCHAR2(100);

BEGIN
    ------------------------------------------------------------------------------
    -- [5] TRUNCATE la tabla PAGO_MOROSO antes de insertar
    ------------------------------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';

    ------------------------------------------------------------------------------
    -- [6] Procesar el cursor
    ------------------------------------------------------------------------------
    OPEN c_morosos;
    LOOP
        ------------------------------------------------------------------------------
        -- 6.1) FETCH datos a variables locales
        ------------------------------------------------------------------------------
        FETCH c_morosos
         INTO v_ate_id,
              v_pac_run,
              v_dv_run,
              v_pnombre,
              v_snombre,
              v_apaterno,
              v_amaterno,
              v_esp_id,
              v_fecha_venc_pago,
              v_fecha_pago,
              v_dias_morosidad,
              v_fecha_nacimiento;

        EXIT WHEN c_morosos%NOTFOUND;

        ------------------------------------------------------------------------------
        -- 6.2) Obtener descuento de tercera edad (PORC_DESCTO_3RA_EDAD)
        ------------------------------------------------------------------------------
        SELECT NVL(MAX(PORCENTAJE_DESCTO), 0)
          INTO v_descuento
          FROM PORC_DESCTO_3RA_EDAD
         WHERE (EXTRACT(YEAR FROM SYSDATE)
                - EXTRACT(YEAR FROM v_fecha_nacimiento)) >= ANNO_INI;

        ------------------------------------------------------------------------------
        -- 6.3) Obtener el nombre de la especialidad
        ------------------------------------------------------------------------------
        SELECT NOMBRE
          INTO v_nombre_especialidad
          FROM ESPECIALIDAD
         WHERE ESP_ID = v_esp_id;

        ------------------------------------------------------------------------------
        -- 6.4) Calcular multa base según la especialidad y días de morosidad
        ------------------------------------------------------------------------------
        CASE v_nombre_especialidad
            WHEN 'Cirugía General' 
                THEN v_multa_total := v_dias_morosidad * v_multas(1);
            WHEN 'Dermatología'
                THEN v_multa_total := v_dias_morosidad * v_multas(1);

            WHEN 'Ortopedia y Traumatología'
                THEN v_multa_total := v_dias_morosidad * v_multas(2);

            WHEN 'Inmunología'
                THEN v_multa_total := v_dias_morosidad * v_multas(3);
            WHEN 'Otorrinolaringología'
                THEN v_multa_total := v_dias_morosidad * v_multas(3);

            WHEN 'Fisiatría'
                THEN v_multa_total := v_dias_morosidad * v_multas(4);
            WHEN 'Medicina Interna'
                THEN v_multa_total := v_dias_morosidad * v_multas(4);

            WHEN 'Medicina General'
                THEN v_multa_total := v_dias_morosidad * v_multas(5);

            WHEN 'Psiquiatría Adultos'
                THEN v_multa_total := v_dias_morosidad * v_multas(6);

            WHEN 'Cirugía Digestiva'
                THEN v_multa_total := v_dias_morosidad * v_multas(7);
            WHEN 'Reumatología'
                THEN v_multa_total := v_dias_morosidad * v_multas(7);

            ELSE
                v_multa_total := 0;
        END CASE;

        ------------------------------------------------------------------------------
        -- 6.5) Aplicar descuento de tercera edad, si corresponde
        ------------------------------------------------------------------------------
        IF v_descuento > 0 THEN
            v_multa_total := v_multa_total - (v_multa_total * (v_descuento / 100));
        END IF;

        ------------------------------------------------------------------------------
        -- 6.6) Insertar datos procesados en PAGO_MOROSO
        ------------------------------------------------------------------------------
        INSERT INTO PAGO_MOROSO (
            PAC_RUN,
            PAC_DV_RUN,
            PAC_NOMBRE,
            ATE_ID,
            FECHA_VENC_PAGO,
            FECHA_PAGO,
            DIAS_MOROSIDAD,
            ESPECIALIDAD_ATENCION,
            MONTO_MULTA
        )
        VALUES (
            v_pac_run,
            v_dv_run,
            v_pnombre || ' ' || v_snombre || ' ' || v_apaterno || ' ' || v_amaterno,
            v_ate_id,
            v_fecha_venc_pago,
            v_fecha_pago,
            v_dias_morosidad,
            v_nombre_especialidad,
            v_multa_total
        );
    END LOOP;

    CLOSE c_morosos;

    ------------------------------------------------------------------------------
    -- [7] Confirmar transacción
    ------------------------------------------------------------------------------
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Proceso completado. Datos insertados en PAGO_MOROSO.');
END;
/


-- Para visualizar tabla
SELECT * FROM PAGO_MOROSO;



