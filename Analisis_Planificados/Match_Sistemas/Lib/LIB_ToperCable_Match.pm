# LIB_ToperCable_Match.pm
#
# Libreria de funciones para Match entre sistemas en alineamiento planificado
# Equivalente a Put_TOPER_MATCH_Alineamiento en alineamiento_planificado_run_MatchFinal.asp

package LIB_ToperCable_Match;

use utf8;
use strict;
use warnings;
use DBI;
use Exporter;
use POSIX "strftime";

# Librerias globales
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    Get_Planificados_Match
    Get_Pendiente_Planificacion
    Put_Match_Alineamiento
    Get_Match_Pendiente
    Get_NumDesalineamientos_Planificado
    UPDATE_Match_Estado
    UPDATE_Match_Desalineamiento
);

use strict;
use warnings;


#------------------------------------------------------------------
# Trim + NULL-to-empty. Equivalente a Limpia() del ASP
sub _Limpia {
    my ($valor) = @_;
    return '' unless defined $valor;
    $valor =~ s/^\s+|\s+$//g;
    return $valor;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve los planificados con estado 0, 1 o 2 pendientes de Match
sub Get_Planificados_Match {

    my ($dbhd, $sthd, $sql);
    my @Items;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT id, nombre, estado FROM topercable.alineamiento_planificado WHERE estado IN (0,1,2) ORDER BY id DESC;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    while (my $row = $sthd->fetchrow_hashref()) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Planificado: $row->{id} | $row->{nombre} | Estado: $row->{estado}");
        push @Items, { id => $row->{id}, nombre => $row->{nombre}, estado => $row->{estado} };
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin. Total: " . scalar(@Items));
    return @Items;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Comprueba si el planificado tiene datos pendientes de procesar.
# Devuelve 0 si todo esta listo para Match, >0 si aun hay pendientes.
sub Get_Pendiente_Planificacion {

    my ($planificado_id) = @_;

    my ($dbhd, $sthd, $sql);

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> planificado_id: $planificado_id");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT SUM( " .
           "    IF(tarifa_sf = '0',1,0) " .
           "    OR IF(tarifa_xena = '0',1,0) " .
           "    OR IF(co_sf = '0',1,0) " .
           "    OR IF(co_xena = '0',1,0) " .
           "    OR IF(co_inv = '0',1,0) " .
           "    OR IF(msa = '0',1,0) " .
           ") PendienteProcesar " .
           "FROM topercable.alineamiento_planificado_detalle " .
           "WHERE planificado_id = $planificado_id;";
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> SQL: $sql");
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    my ($pendiente) = $sthd->fetchrow_array();
    $pendiente = 0 unless defined $pendiente;

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> PendienteProcesar: $pendiente");
    return $pendiente;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Ejecuta el MATCH para los MSISDN pendientes de un planificado.
# Calcula RESULTADO por MSISDN y lo guarda en batch.
# Equivalente a Put_TOPER_MATCH_Alineamiento() del ASP.
sub Put_Match_Alineamiento {

    my ($planificado_id) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> planificado_id: $planificado_id");

    unless (defined $planificado_id && $planificado_id =~ /^\d+$/ && $planificado_id > 0) {
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> ERROR: planificado_id invalido");
        return -1;
    }

    my ($dbhd, $sthd, $sql);
    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT id, planificado_id, msisdn, msa, co_sf, co_xena, co_inv, " .
           "resi_sf, resi_xena, resi_inv, cif_sf, cif_xena, " .
           "tarifa_sf, tarifa_xena, bc_sf, bc_xena, promo_sf, promo_xena, " .
           "imsi_msa, imsi_sf, imsi_xena, ultimocambio " .
           "FROM topercable.alineamiento_planificado_detalle " .
           "WHERE planificado_id = $planificado_id AND (result = '0' OR result IS NULL) " .
           "ORDER BY co_xena, resi_xena, msisdn LIMIT 100000;";
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> SQL: $sql");
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    my @sql_batch;
    my $batch_size     = 100;
    my $num_procesados = 0;

    while (my $row = $sthd->fetchrow_hashref()) {

        my $ID    = $row->{id};
        my $MSA   = $row->{msa} // '';

        # Limpia aplicada igual que en el ASP (no se aplica a MSA, CO_INV, RESI_INV)
        my $CO_SF       = _Limpia($row->{co_sf});
        my $CO_XENA     = _Limpia($row->{co_xena});
        my $CO_INV      = $row->{co_inv}    // '';
        my $RESI_SF     = _Limpia($row->{resi_sf});
        my $RESI_XENA   = _Limpia($row->{resi_xena});
        my $RESI_INV    = $row->{resi_inv}  // '';
        my $CIF_SF      = _Limpia($row->{cif_sf});
        my $CIF_XENA    = _Limpia($row->{cif_xena});
        my $TARIFA_SF   = _Limpia($row->{tarifa_sf});
        my $TARIFA_XENA = _Limpia($row->{tarifa_xena});
        my $BC_SF       = _Limpia($row->{bc_sf});
        my $BC_XENA     = _Limpia($row->{bc_xena});
        my $PROMO_SF    = _Limpia($row->{promo_sf});
        my $PROMO_XENA  = _Limpia($row->{promo_xena});
        my $IMSI_MSA    = _Limpia($row->{imsi_msa});
        my $IMSI_SF     = _Limpia($row->{imsi_sf});
        my $IMSI_XENA   = _Limpia($row->{imsi_xena});

        # -----------------------------------------------
        # Logica de MATCH (orden identico al ASP: cada
        # regla posterior sobreescribe a la anterior)
        # -----------------------------------------------
        my $RESULTADO = "OK";

        # ERROR_INV
        if ($MSA eq "CONNECTED"
            && ($CO_XENA ne '' || $CO_SF ne '')
            && ($CO_INV ne $CO_XENA || $RESI_INV ne $RESI_XENA))
        {
            $RESULTADO = "ERROR_INV";
        }

        # ERROR_TAR / ERROR_BCO / ERROR_PRO (exclusivos entre si)
        if ($TARIFA_XENA ne $TARIFA_SF) {
            $RESULTADO = "ERROR_TAR";
        } elsif ($BC_XENA ne $BC_SF) {
            $RESULTADO = "ERROR_BCO";
        } elsif ($PROMO_XENA ne $PROMO_SF) {
            $RESULTADO = "ERROR_PRO";
        }

        # ERROR_CODSF: primeros 6 digitos de RESI_SF deben coincidir con CO_SF
        if ($MSA eq "CONNECTED" && substr($RESI_SF, 0, 6) ne $CO_SF) {
            $RESULTADO = "ERROR_CODSF";
        }

        # ERROR_IMSI: fuente de verdad = imsi_msa; basta que uno de los otros difiera
        if ($IMSI_MSA ne '' && ($IMSI_SF ne $IMSI_MSA || $IMSI_XENA ne $IMSI_MSA)) {
            $RESULTADO = "ERROR_IMSI";
        }

        # ERROR_CIF
        if ($MSA eq "CONNECTED" && $CIF_XENA ne $CIF_SF) {
            $RESULTADO = "ERROR_CIF";
        }

        # ERROR_COD
        if ($MSA eq "CONNECTED" && ($RESI_SF ne $RESI_XENA || $CO_SF ne $CO_XENA)) {
            $RESULTADO = "ERROR_COD";
        }

        # ERROR_AST: linea asignada en Xena pero sin asignar en SF
        if ($MSA eq "CONNECTED" && $RESI_XENA ne '' && ($RESI_SF eq '' || $CO_SF eq '')) {
            $RESULTADO = "ERROR_AST";
        }

        # ERROR_MSA: no CONNECTED pero tiene datos en SF o Xena
        if ($MSA ne "CONNECTED" && ($RESI_SF ne '' || $RESI_XENA ne '')) {
            $RESULTADO = "ERROR_MSA";
        }
        # -----------------------------------------------

        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> id: $ID | MSA: $MSA | RESULTADO: $RESULTADO");

        my $sqlu = "UPDATE topercable.alineamiento_planificado_detalle SET result = '$RESULTADO' WHERE id = $ID;";
        push @sql_batch, $sqlu;

        if (scalar(@sql_batch) >= $batch_size) {
            _Batch_Match_Ejecutar(\@sql_batch);
        }

        $num_procesados++;
    }

    # Ejecutamos el resto del batch
    if (@sql_batch) {
        _Batch_Match_Ejecutar(\@sql_batch);
    }

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Total procesados: $num_procesados");
    return 1;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Cuenta los MSISDN que aun no tienen resultado (result = '0' o NULL)
sub Get_Match_Pendiente {

    my ($planificado_id) = @_;

    my ($dbhd, $sthd, $sql);

    my $nombre_modulo = (caller(0))[3];

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT COUNT(id) FROM topercable.alineamiento_planificado_detalle " .
           "WHERE planificado_id = $planificado_id AND (result = '0' OR result IS NULL);";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    my ($pendiente) = $sthd->fetchrow_array();
    $pendiente = 0 unless defined $pendiente;

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> MatchPendiente: $pendiente");
    return $pendiente;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Cuenta los errores del planificado. Excluye ERROR_MSA sin CO_SF asignado
# (indica baja, no desalineamiento real)
sub Get_NumDesalineamientos_Planificado {

    my ($planificado_id) = @_;

    my ($dbhd, $sthd, $sql);

    my $nombre_modulo = (caller(0))[3];

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT COUNT(id) FROM topercable.alineamiento_planificado_detalle " .
           "WHERE planificado_id = $planificado_id AND result LIKE 'ERROR_%' " .
           "AND NOT (result = 'ERROR_MSA' AND (co_sf IS NULL OR co_sf = ''));";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    my ($num_errores) = $sthd->fetchrow_array();
    $num_errores = 0 unless defined $num_errores;

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> NumDesalineamientos: $num_errores");
    return $num_errores;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Actualiza el campo estado del planificado
sub UPDATE_Match_Estado {

    my ($planificado_id, $estado) = @_;

    my ($dbhd, $sthd, $sql);

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> planificado_id: $planificado_id | nuevo estado: $estado");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "UPDATE topercable.alineamiento_planificado SET estado = $estado WHERE id = $planificado_id;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> OK");
    return 1;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Actualiza el campo errores del planificado
sub UPDATE_Match_Desalineamiento {

    my ($planificado_id, $num_errores) = @_;

    my ($dbhd, $sthd, $sql);

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> planificado_id: $planificado_id | desalineamientos: $num_errores");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "UPDATE topercable.alineamiento_planificado SET errores = $num_errores WHERE id = $planificado_id;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> OK");
    return 1;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Ejecuta el lote acumulado de UPDATEs y limpia el array
sub _Batch_Match_Ejecutar {

    my ($lote_ref) = @_;

    my $nombre_modulo = (caller(0))[3];

    my $num_sqls = scalar(@$lote_ref);
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Sentencias en lote: $num_sqls");

    return unless $num_sqls > 0;

    my $sql_total = join("\n", @$lote_ref);

    my $dbhd = ConectarDB->connect_topercable_multi_statement();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Ejecutando UPDATE batch Match ($num_sqls sentencias)..");
    my $rows = $dbhd->do($sql_total);
    if (!defined $rows) {
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> ERROR ejecutando batch SQL Match: $DBI::errstr");
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> SQL: $sql_total");
    } else {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Batch ejecutado OK. Filas afectadas: $rows");
    }

    @$lote_ref = ();
}
#------------------------------------------------------------------


1;      # FIN DEL MODULO
