# LIB_ToperCable_Inventario.pm
#
# Libreria de funciones para extraccion de datos de Inventario BPM
# Equivalente a Get_INV_MSISDN_data en alineamiento_planificado_run_inventario.asp
# Dos endpoints: CO (primario) y SME (fallback)

package LIB_ToperCable_Inventario;

use utf8;
use strict;
use warnings;
use DBI;
use Exporter;
use POSIX "strftime";
use LWP::UserAgent;
use HTTP::Request;
use JSON;
use Encode qw(encode);

# Librerias globales
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    Get_Planificados_Pendientes_Inventario
    Get_MSISDN_Pendientes_Inventario
    Get_INV_MSISDN_Data
    UPDATE_INV_Contador
    Batch_INV_SQL_Generar
    Batch_INV_SQL_Ejecutar
);

use strict;
use warnings;

# Configuracion API Inventario
my $INV_CO_URL  = "https://repository-engine.private.prod-01.k8s.masmovil.com/cableoperators/lines";
my $INV_SME_URL = "https://inventory-operations.private.prod-01.k8s.masmovil.com/resources/msisdn";
my $INV_TIMEOUT = 5;


#------------------------------------------------------------------
# Devuelve los IDs de planificados pendientes (estado < 2)
sub Get_Planificados_Pendientes_Inventario {

    my ($dbhd, $sthd, $sql);
    my @AiTems;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT id FROM topercable.alineamiento_planificado WHERE estado < 2 ORDER BY prioridad, id DESC LIMIT 10;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    while (defined(my $item = $sthd->fetchrow_array())) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Planificado: $item");
        push @AiTems, $item;
    }

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin");
    return @AiTems;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Devuelve los registros pendientes de Inventario para un planificado.
# Retorna array de hashrefs {id, msisdn} ya que el UPDATE usa el id de detalle.
sub Get_MSISDN_Pendientes_Inventario {

    my ($planificado_id) = @_;

    my ($dbhd, $sthd, $sql);
    my @AiTems;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> planificado_id: $planificado_id");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT id, msisdn FROM topercable.alineamiento_planificado_detalle " .
           "WHERE planificado_id = $planificado_id AND resi_inv = '0' ORDER BY id LIMIT 10000;";
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> SQL: $sql");
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    while (my $row = $sthd->fetchrow_hashref()) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> id: $row->{id} | msisdn: $row->{msisdn}");
        push @AiTems, { id => $row->{id}, msisdn => $row->{msisdn} };
    }

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Total pendientes Inventario: " . scalar(@AiTems));
    return @AiTems;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Consulta Inventario BPM para un MSISDN.
# Intenta primero el endpoint CO; si falla, el endpoint SME.
# Equivalente a Get_INV_MSISDN_data() del ASP.
sub Get_INV_MSISDN_Data {

    my ($msisdn) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> msisdn: $msisdn");

    unless ($msisdn) {
        return { result => 0, msg => "ERROR: msisdn no recibido." };
    }

    my $ua = LWP::UserAgent->new(timeout => $INV_TIMEOUT);
    $ua->ssl_opts(verify_hostname => 0, SSL_verify_mode => 0);

    #------------------------------------------------------
    # Endpoint CO (primario)
    #------------------------------------------------------
    my $url_co = "$INV_CO_URL/$msisdn";
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Consultando CO: $url_co");

    my $response_co = $ua->get($url_co);

    if ($response_co->is_success) {
        my $decoded;
        eval {
            $decoded = decode_json(encode("UTF-8", $response_co->decoded_content));
            1;
        } or do {
            Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR JSON CO para MSISDN: $msisdn");
            return { result => 0, msg => "[Error.INV.CO.JSON]" };
        };

        my $cablero     = $decoded->{cable_operator_code} // '';
        my $residencial = $decoded->{residential_id}      // '';
        my $tarifa      = $decoded->{rate_name}           // '';
        my $marca       = $cablero ne '' ? 'Cablemovil' : 'YOIGO EMPRESAS';

        $cablero     =~ s/^\s+|\s+$//g;
        $residencial =~ s/^\s+|\s+$//g;
        $tarifa      =~ s/^\s+|\s+$//g;

        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> CO OK | Cablero: $cablero | Residencial: $residencial | Tarifa: $tarifa | Marca: $marca");

        return {
            result      => 1,
            endpoint    => 'CO',
            Cablero     => $cablero,
            Residencial => $residencial,
            Tarifa      => $tarifa,
            Marca       => $marca,
        };
    }

    my $http_co = $response_co->code;
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> CO HTTP $http_co para MSISDN: $msisdn. Probando SME..");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> CO Body: " . $response_co->decoded_content);

    #------------------------------------------------------
    # Endpoint SME (fallback)
    #------------------------------------------------------
    my $url_sme = "$INV_SME_URL/$msisdn";
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Consultando SME: $url_sme");

    my $response_sme = $ua->get($url_sme);

    if ($response_sme->is_success) {
        my $decoded;
        eval {
            $decoded = decode_json(encode("UTF-8", $response_sme->decoded_content));
            1;
        } or do {
            Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR JSON SME para MSISDN: $msisdn");
            return { result => 0, msg => "[Error.INV.SME.JSON]" };
        };

        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> SME OK | Cablero: SME | Residencial: SME");

        return {
            result      => 1,
            endpoint    => 'SME',
            Cablero     => 'SME',
            Residencial => 'SME',
            Tarifa      => '',
            Marca       => 'SME',
        };
    }

    my $http_sme = $response_sme->code;
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> SME Body: " . $response_sme->decoded_content);
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Ambos endpoints fallaron para MSISDN: $msisdn (CO: $http_co | SME: $http_sme)");
    return { result => 0, msg => "[Error.INV.HTTP.CO=$http_co.SME=$http_sme]" };
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Actualiza el contador chk_inventario del planificado
sub UPDATE_INV_Contador {

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

    $sql = "UPDATE topercable.alineamiento_planificado " .
           "SET chk_inventario = (SELECT SUM(IF(resi_inv = '0', 0, 1)) PROCESADOS " .
           "FROM topercable.alineamiento_planificado_detalle WHERE planificado_id = $planificado_id) " .
           "WHERE ID = $planificado_id;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin");
    return 1;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Acumula SQLs en lote y los ejecuta al llegar al umbral
sub Batch_INV_SQL_Generar {

    my ($sql_ref, $lote_ref, $batch_size) = @_;

    push @$lote_ref, $$sql_ref;

    if (scalar(@$lote_ref) >= $batch_size) {
        Batch_INV_SQL_Ejecutar($lote_ref);
    }

    $$sql_ref = "";
}

# Ejecuta el lote acumulado y limpia el array
sub Batch_INV_SQL_Ejecutar {

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

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Ejecutando UPDATE batch Inventario ($num_sqls sentencias)..");
    my $rows = $dbhd->do($sql_total);
    if (!defined $rows) {
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> ERROR ejecutando batch SQL Inventario: $DBI::errstr");
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> SQL: $sql_total");
    } else {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Batch ejecutado OK. Filas afectadas: $rows");
    }

    @$lote_ref = ();
}
#------------------------------------------------------------------


1;      # FIN DEL MODULO
