# LIB_ToperCable_Xena.pm
#
# Libreria de funciones para extraccion directa de datos Xena (mvno)
# Refactorizacion de alineamiento_planificado_run_xena.asp

package LIB_ToperCable_Xena;

use utf8;
use strict;
use warnings;
use DBI;
use Exporter;
use Switch;
use POSIX "strftime";
use DateTime::Locale;
use Time::Local;
use Data::Dumper qw(Dumper);

# Librerias globales
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    Get_Planificados_Pendientes_Xena
    Get_MSISDN_Pendientes_Xena
    Get_Xena_MSISDN_Data
    Get_Xena_Cliente_Data
    Get_Xena_BonoCom
    Get_Xena_Promos
    Ordenar_Xena_Promos
    UPDATE_Xena_Contador
    Batch_Xena_SQL_Generar
    Batch_Xena_SQL_Ejecutar
);

use strict;
use warnings;


#------------------------------------------------------------------
# Devuelve los IDs de planificados pendientes (estado < 2)
sub Get_Planificados_Pendientes_Xena {

    my ($dbhd, $sthd, $sql);
    my (@AiTems, $item);

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT id FROM topercable.alineamiento_planificado WHERE estado < 2 AND tipo NOT IN ('Cartera') ORDER BY prioridad, id DESC LIMIT 10;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    while (defined(my $item = $sthd->fetchrow_array())) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Planificado: $item");
        push(@AiTems, $item);
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin");
    return @AiTems;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve MSISDNs pendientes de extraccion Xena para un planificado
sub Get_MSISDN_Pendientes_Xena {

    my ($planificado_id) = @_;

    my ($dbhd, $sthd, $sql);
    my (@AiTems);

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> planificado_id: $planificado_id");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT DISTINCT msisdn FROM topercable.alineamiento_planificado_detalle WHERE planificado_id = $planificado_id AND (co_xena='0' OR imsi_xena='0') ORDER BY id DESC LIMIT 2000;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    while (defined(my $item = $sthd->fetchrow_array())) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> MSISDN: $item");
        push(@AiTems, $item);
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Total: " . scalar(@AiTems));
    return @AiTems;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve los datos principales del MSISDN desde mvno.pv_msisdn:
#   CO, Residencial, Estado, migradoCRM, IMSI, idPerfil, Tarifa_des
sub Get_Xena_MSISDN_Data {

    my ($msisdn) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> msisdn: $msisdn");

    unless ($msisdn) {
        return { result => 0, msg => "ERROR: msisdn no recibido." };
    }

    my ($dbhd, $sthd, $sql);

    $dbhd = ConectarDB->connect_xena_mvno();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR. No se pudo conectar Xena mvno. ($DBI::errstr)");
        return { result => 0, msg => "ERROR CONEXION Xena mvno: $DBI::errstr" };
    }

    $sql = "SELECT
                a.msisdn,
                a.id_estado_actual,
                a.id_cliente_fact  AS CO,
                a.id_cliente       AS Residencial,
                a.migradoCRM,
                a.imsi,
                p.id_perfil        AS idPerfil,
                p.descripcion      AS Tarifa_des
            FROM mvno.pv_msisdn a
            LEFT JOIN mvno.pv_mvno_perfiles_clientes p
                ON a.id_producto = p.id_producto AND p.Flag_Activo = 'S'
            WHERE a.msisdn = '$msisdn'
              AND a.id_estado_actual NOT IN ('B', 'D')
            ORDER BY a.Fecha_Activacion DESC
            LIMIT 1";

    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or return { result => 0, msg => "Error SQL pv_msisdn: " . $sthd->errstr };

    my $row = $sthd->fetchrow_hashref();
    unless ($row) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> No existe registro activo para MSISDN: $msisdn");
        return { result => 0, msg => "MSISDN no existe en Xena o esta dado de baja" };
    }

    # Trim al IMSI por si viene con espacios
    my $imsi_limpio = $row->{imsi} // '';
    $imsi_limpio =~ s/^\s+|\s+$//g;

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> CO: $row->{CO} | Resi: $row->{Residencial} | idPerfil: $row->{idPerfil} | IMSI: $imsi_limpio");

    return {
        result      => 1,
        CO          => $row->{CO}               // '',
        Residencial => $row->{Residencial}       // '',
        Estado      => $row->{id_estado_actual}  // '',
        migradoCRM  => $row->{migradoCRM}        // '',
        imsi        => $imsi_limpio,
        idPerfil    => $row->{idPerfil}          // '',
        Tarifa_des  => $row->{Tarifa_des}        // '',
    };
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve NIF y datos del cliente Xena a partir del id_cliente (Residencial)
# Equivalente a Get_XENA_CLIENTE_data() en include_objetos_Xena.asp
# Tabla: xprv.pv_clientes (MySQL — equivalente a dbo.pv_clientes de SQL Server)
sub Get_Xena_Cliente_Data {

    my ($id_cliente) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> id_cliente: $id_cliente");

    unless (defined $id_cliente && $id_cliente ne '' && $id_cliente ne '0') {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> id_cliente vacio, saltando");
        return { result => 0, msg => "id_cliente no recibido." };
    }

    my ($dbhd, $sthd, $sql);

    $dbhd = ConectarDB->connect_xena_xprv();
    if (not defined $dbhd) {
        return { result => 0, msg => "ERROR CONEXION Xena xprv: $DBI::errstr" };
    }

    $sql = "SELECT id_cliente_fact AS CO, id_cliente AS Residencial, nif, TRIM(Nombre) AS nombre, " .
           "Fecha_Alta, MigradoCRM, TRIM(Direccion) AS direccion, TRIM(Poblacion) AS poblacion " .
           "FROM xprv.pv_clientes " .
           "WHERE id_cliente = '$id_cliente' " .
           "ORDER BY Fecha_Alta DESC LIMIT 1";

    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or return { result => 0, msg => "Error SQL xprv.pv_clientes: " . $sthd->errstr };

    my $row = $sthd->fetchrow_hashref();
    unless ($row) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Cliente no encontrado: $id_cliente");
        return { result => 0, msg => "Cliente no existe en Xena: $id_cliente" };
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> NIF: $row->{nif}");

    return {
        result    => 1,
        NIF       => $row->{nif}       // '',
        Nombre    => $row->{nombre}    // '',
        Falta     => $row->{Fecha_Alta} // '',
        Migrado   => $row->{MigradoCRM} // '',
        CO        => $row->{CO}        // '',
        Direccion => $row->{direccion} // '',
        Poblacion => $row->{poblacion} // '',
    };
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve el codigo de Bono Compartido Xena para un MSISDN
# Equivalente a Xena_BonoCom en Get_XENA_MSISDN_data / Get_XENA_MSISDN_data_v2
# Tabla: mvno.pv_mvno_bonos_msisdn JOIN mvno.pv_mvno_bonos
sub Get_Xena_BonoCom {

    my ($id_cliente, $msisdn) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> id_cliente: $id_cliente | msisdn: $msisdn");

    unless ($id_cliente && $msisdn) {
        return { result => 1, BonoCom => '' };
    }

    my ($dbhd, $sthd, $sql);
    $dbhd = ConectarDB->connect_xena_mvno();
    if (not defined $dbhd) {
        return { result => 0, msg => "ERROR CONEXION Xena mvno: $DBI::errstr" };
    }

    $sql = "SELECT GROUP_CONCAT(b.Id_bono) AS Bono_Compartido, " .
           "GROUP_CONCAT(b.parametro_a) AS Parametro_A, " .
           "GROUP_CONCAT(c.descripcion) AS BONO_CODE_Descripcion " .
           "FROM mvno.pv_mvno_bonos_msisdn b " .
           "LEFT JOIN mvno.pv_mvno_bonos c ON b.id_bono = c.id_bono AND c.Fecha_Fin >= DATE_FORMAT(CURDATE(), '%Y%m%d') " .
           "WHERE b.msisdn = '$msisdn' " .
           "AND b.id_cliente = '$id_cliente' " .
           "AND b.Flag_Activado = 'S' " .
           "AND b.Parametro_A != '' " .
           "AND b.Id_Bono NOT IN ( " .
           "    SELECT p.Bonos_Defecto FROM mvno.pv_msisdn a " .
           "    JOIN mvno.pv_mvno_perfiles_clientes p ON a.id_producto = p.id_producto AND p.Flag_Activo = 'S' " .
           "    WHERE a.msisdn = '$msisdn' " .
           ") " .
           "GROUP BY b.msisdn";

    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or return { result => 0, msg => "Error SQL pv_mvno_bonos_msisdn: " . $sthd->errstr };

    my $row = $sthd->fetchrow_hashref();
    my $bono_com = '';
    if ($row && defined $row->{Bono_Compartido}) {
        $bono_com = $row->{Bono_Compartido};
        $bono_com =~ s/^\s+|\s+$//g;
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> BonoCom: $bono_com");
    return { result => 1, BonoCom => $bono_com };
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve los codigos de Promociones Xena para un MSISDN
# Equivalente a Xena_Promo en Get_XENA_MSISDN_data_v2
# Tabla: mvno.pv_productos_retencion_msisdn JOIN mvno.pv_productos_retencion
sub Get_Xena_Promos {

    my ($id_cliente, $msisdn) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> id_cliente: $id_cliente | msisdn: $msisdn");

    unless ($id_cliente && $msisdn) {
        return { result => 1, Promos => '' };
    }

    my ($dbhd, $sthd, $sql);
    $dbhd = ConectarDB->connect_xena_mvno();
    if (not defined $dbhd) {
        return { result => 0, msg => "ERROR CONEXION Xena mvno: $DBI::errstr" };
    }

    $sql = "SELECT GROUP_CONCAT(a.Id_Producto_Retencion) AS Bono_PROMOCION, " .
           "GROUP_CONCAT(b.descripcion) AS Promo_Desc " .
           "FROM mvno.pv_productos_retencion_msisdn a " .
           "JOIN mvno.pv_productos_retencion b ON a.Id_Producto_Retencion = b.id_Producto_Retencion " .
           "WHERE a.msisdn = '$msisdn' " .
           "AND a.id_cliente = '$id_cliente' " .
           "AND (a.fecha_fin > CURDATE() OR a.fecha_fin = '') " .
           "AND (a.Fecha_Desactivacion = '' OR a.Fecha_Desactivacion > CURDATE()) " .
           "GROUP BY a.MSISDN";

    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or return { result => 0, msg => "Error SQL pv_productos_retencion_msisdn: " . $sthd->errstr };

    my $row = $sthd->fetchrow_hashref();
    my $promos = '';
    if ($row && defined $row->{Bono_PROMOCION}) {
        $promos = $row->{Bono_PROMOCION};
        $promos =~ s/^\s+|\s+$//g;
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Promos: $promos");
    return { result => 1, Promos => $promos };
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Ordena alfabeticamente los codigos de promo separados por coma
# Equivalente a Ordenar_Variable_Alfanumerica del ASP
sub Ordenar_Xena_Promos {

    my ($promos_str) = @_;
    return '' unless defined $promos_str && $promos_str ne '';

    my @promos = split(/,/, $promos_str);
    @promos = map { $_ =~ s/^\s+|\s+$//gr } @promos;   # trim cada elemento
    @promos = sort @promos;

    return join(',', @promos);
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Actualiza el contador chk_xena del planificado
# Equivalente al UPDATE final del ASP
sub UPDATE_Xena_Contador {

    my ($planificado_id) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> planificado_id: $planificado_id");

    unless ($planificado_id) {
        return { result => 0, msg => "planificado_id no recibido." };
    }

    my ($dbhd, $sthd, $sql);

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "UPDATE topercable.alineamiento_planificado SET chk_xena = (SELECT SUM(IF(tarifa_xena = '0', 0, 1)) PROCESADOS FROM topercable.alineamiento_planificado_detalle WHERE planificado_id = $planificado_id) WHERE ID = $planificado_id;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin");
    return 1;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Acumula SQLs en lote y los ejecuta al llegar al umbral
sub Batch_Xena_SQL_Generar {

    my ($sql_ref, $lote_ref, $batch_size) = @_;

    push @$lote_ref, $$sql_ref;

    Plogged($log_file, $modo_ejecucion, 0, "\t\t - Generando SQL update Xena");
    if (scalar(@$lote_ref) >= $batch_size) {
        Plogged($log_file, $modo_ejecucion, 0, "\t\t - Umbral alcanzado, ejecutando batch Xena");
        Batch_Xena_SQL_Ejecutar($lote_ref);
    }

    $$sql_ref = "";
}

# Ejecuta el lote acumulado y limpia el array
sub Batch_Xena_SQL_Ejecutar {

    my ($lote_ref) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio");

    my $sql_total = join("\n", @$lote_ref);

    my ($dbhd);
    $dbhd = ConectarDB->connect_topercable_multi_statement();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    if ($sql_total ne '') {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Ejecutando UPDATE batch Xena..");
        $dbhd->do($sql_total) or warn "Error en batch SQL Xena: $DBI::errstr";
    }

    @$lote_ref = ();
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin");
}
#------------------------------------------------------------------


1;      # FIN DEL MODULO
