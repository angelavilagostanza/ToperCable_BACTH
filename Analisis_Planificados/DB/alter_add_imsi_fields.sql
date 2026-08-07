-- ============================================================
--  Ampliar alineamiento_planificado_detalle con campos IMSI
--  Un campo por sistema: Salesforce, Xena, MSA
--  Valor '0' = pendiente de extraer (mismo convenio que co_sf, resi_sf, etc.)
-- ============================================================

ALTER TABLE topercable.alineamiento_planificado_detalle
    ADD COLUMN imsi_sf   VARCHAR(50) NOT NULL DEFAULT '0'  AFTER promo_sf,
    ADD COLUMN imsi_xena VARCHAR(50) NOT NULL DEFAULT '0'  AFTER imsi_sf,
    ADD COLUMN imsi_msa  VARCHAR(50) NOT NULL DEFAULT '0'  AFTER imsi_xena;
