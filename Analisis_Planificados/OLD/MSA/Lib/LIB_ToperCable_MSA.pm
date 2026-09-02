# LIB_ToperCable_MSA.pm
#
# Libreria de funciones para extraccion de IMSI desde MSA (API REST HLR)
# Equivalente a Get_MSA_MSISDN_data_v2_OLD en include_objetos_MSA.asp

package LIB_ToperCable_MSA;

use utf8;
use strict;
use warnings;
use DBI;
use Exporter;
use POSIX "strftime";
use LWP::UserAgent;
use JSON;
use Encode qw(encode);
use Data::Dumper qw(Dumper);

# Librerias globales
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    Get_Planificados_Pendientes_MSA
    Get_MSISDN_Pendientes_MSA
    Get_MSA_MSISDN_Data
    UPDATE_MSA_Contador
    Batch_MSA_SQL_Generar
    Batch_MSA_SQL_Ejecutar
);

use strict;
use warnings;

# Configuracion MSA API
my $MSA_API_URL     = "https://apigw.mm-red.net/voice-mobile/northbound-common/msisdns";
my $MSA_API_KEY     = "0ac56e95-3b7e-40b8-806f-a97bce016fe1";
my $MSA_API_TIMEOUT = 15;


#------------------------------------------------------------------
# Devuelve los IDs de planificados pendientes (estado < 2)
sub Get_Planificados_Pendientes_MSA {

    my ($dbhd, $sthd, $sql);
    my (@AiTems);

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
# Devuelve MSISDNs pendientes de extraccion IMSI MSA para un planificado
sub Get_MSISDN_Pendientes_MSA {

    my ($planificado_id) = @_;

    my ($dbhd, $sthd, $sql);
    my (@AiTems);

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> planificado_id: $planificado_id");

    $dbhd = ConectarDB->connect_topercable();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    $sql = "SELECT DISTINCT msisdn FROM topercable.alineamiento_planificado_detalle WHERE planificado_id = $planificado_id AND imsi_msa = '0' ORDER BY id DESC LIMIT 2000;";
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> SQL: $sql");
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    while (defined(my $item = $sthd->fetchrow_array())) {
        Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> MSISDN: $item");
        push(@AiTems, $item);
    }

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Total MSISDNs pendientes MSA: " . scalar(@AiTems));
    return @AiTems;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Llama al endpoint MSA HLR y devuelve IMSI, estado y datos de marca
# GET https://apigw.mm-red.net/voice-mobile/northbound-common/msisdns/{msisdn}/hlr
# Equivalente a Get_MSA_MSISDN_data_v2_OLD en include_objetos_MSA.asp
sub Get_MSA_MSISDN_Data {

    my ($msisdn) = @_;

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> msisdn: $msisdn");

    unless ($msisdn) {
        return { result => 0, msg => "ERROR: msisdn no recibido." };
    }

    my $url = "$MSA_API_URL/$msisdn/hlr";

    my $ua = LWP::UserAgent->new(timeout => $MSA_API_TIMEOUT);
    $ua->ssl_opts(verify_hostname => 0, SSL_verify_mode => 0);

    my $request = HTTP::Request->new(GET => $url);
    $request->header('accept'    => 'application/json');
    $request->header('X-API-KEY' => $MSA_API_KEY);

    my $response = $ua->request($request);

    unless ($response->is_success) {
        my $http_code = $response->code;
        if ($http_code == 400) {
            Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> NO EXISTE el MSISDN en MSA: $msisdn");
            return { result => 0, msg => "[MSA.NoExiste]" };
        }
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR HTTP $http_code para MSISDN: $msisdn");
        return { result => 0, msg => "[Error.MSA.HTTP.$http_code]" };
    }

    # Parsear JSON de respuesta
    my $decoded;
    eval {
        $decoded = decode_json(encode("UTF-8", $response->decoded_content));
        1;
    } or do {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR JSON para MSISDN: $msisdn");
        return { result => 0, msg => "[Error.MSA.JSON]" };
    };

    # Verificar que existe el objeto data
    unless (ref($decoded) eq 'HASH' && exists $decoded->{data}) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Sin datos en respuesta para MSISDN: $msisdn");
        return { result => 0, msg => "[Error.MSA.NoData]" };
    }

    my $data   = $decoded->{data};
    my $imsi   = $data->{imsi}        // '';
    my $estado = $data->{msisdnstate} // '';

    $imsi   =~ s/^\s+|\s+$//g;
    $estado =~ s/^\s+|\s+$//g;

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> IMSI: $imsi | Estado: $estado");

    # Determinar brand/crm/bss a partir de los digitos 6-8 del IMSI
    my ($brand, $crm, $bss) = _Get_MSA_Brand_From_IMSI($imsi);

    return {
        result => 1,
        imsi   => $imsi,
        estado => $estado,
        brand  => $brand,
        crm    => $crm,
        bss    => $bss,
    };
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Determina Brand/CRM/BSS a partir del IMSI (digitos 6-8 y 6)
# Equivalente al diccionario imsiConfig del ASP
sub _Get_MSA_Brand_From_IMSI {

    my ($imsi) = @_;
    return ('Desconocido', 'Desconocido', 'Desconocido') unless defined $imsi && length($imsi) >= 8;

    # Mapa: rango_3_digitos => "Brand|CRM|BSS"
    my %imsi_config = (
        '200' => 'MasMovil|MySIM|Residencial',
        '201' => 'MasMovil|MySIM|Residencial',
        '223' => 'Parlem|MySIM|Residencial',
        '220' => 'Alterna|MySIM|Residencial',
        '224' => 'JOI|MySIM|Residencial',
        '280' => 'Llamaya|MySIM|Residencial',
        '290' => 'Pepephone|HEOS|Residencial',
        '211' => 'Adamo|Salesforce|Empresas',
        '212' => 'Cableworld|Salesforce|Empresas',
        '202' => 'Yoigo|Salesforce|Empresas',
        '203' => 'Yoigo|Salesforce|Empresas',
        '270' => 'Lebara|Qvantel_Prepago|Residencial',
        '250' => 'Lyca|Qvantel_Prepago|Residencial',
        '204' => 'MasMovil|N/A|Empresas',
        '205' => 'MasMovil|N/A|Empresas',
        '206' => 'Cablemovil|Salesforce|Empresas',
        '207' => 'Cablemovil|Salesforce|Empresas',
        '210' => 'Cablemovil|Salesforce|Empresas',
        '208' => 'MarcasBlancas|Salesforce|Empresas',
        '209' => 'MarcasBlancas|Salesforce|Empresas',
        '230' => 'Euskaltel|EKTNET|Euskaltel Euskadi',
        '232' => 'Euskaltel|EKTNET|Euskaltel Euskadi',
        '240' => 'Euskaltel|EKTNET|Euskaltel Euskadi',
        '231' => 'Telecable|TCNET|Telecable Asturias',
        '233' => 'Telecable|TCNET|Telecable Asturias',
        '234' => 'RCABLE|SIEBEL|RCABLE Galicia',
        '235' => 'RCABLE|SIEBEL|RCABLE Galicia',
        '238' => 'RCABLE|SIEBEL|RCABLE Galicia',
        '239' => 'RCABLE|SIEBEL|RCABLE Galicia',
        # Fallback 1 digito
        '0'   => 'Yoigo|TMS|Residencial',
        '1'   => 'Yoigo|TMS|Residencial',
        '2'   => 'Yoigo|TMS|Residencial',
        '5'   => 'Several Brands|MVNE|Empresas',
    );

    my $range3 = substr($imsi, 5, 3);    # posiciones 6,7,8 (base 0: 5,6,7)
    my $range1 = substr($imsi, 5, 1);    # posicion 6 (base 0: 5)

    my $key = exists $imsi_config{$range3} ? $range3
            : exists $imsi_config{$range1} ? $range1
            : undef;

    unless (defined $key) {
        return ('Desconocido', 'Desconocido', 'Desconocido');
    }

    my @parts = split(/\|/, $imsi_config{$key});
    return ($parts[0], $parts[1], $parts[2]);
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Actualiza el contador chk_msa del planificado
sub UPDATE_MSA_Contador {

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

    $sql = "UPDATE topercable.alineamiento_planificado SET chk_msa = (SELECT SUM(IF(imsi_msa = '0', 0, 1)) PROCESADOS FROM topercable.alineamiento_planificado_detalle WHERE planificado_id = $planificado_id) WHERE ID = $planificado_id;";
    $sthd = $dbhd->prepare($sql);
    $sthd->execute() or die "No se pudo ejecutar la consulta. SQL:($sql) Desc(" . $sthd->errstr . ")";

    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Fin");
    return 1;
}
#------------------------------------------------------------------


#------------------------------------------------------------------
# Acumula SQLs en lote y los ejecuta al llegar al umbral
sub Batch_MSA_SQL_Generar {

    my ($sql_ref, $lote_ref, $batch_size) = @_;

    push @$lote_ref, $$sql_ref;

    Plogged($log_file, $modo_ejecucion, 0, "\t\t - Generando SQL update MSA");
    if (scalar(@$lote_ref) >= $batch_size) {
        Plogged($log_file, $modo_ejecucion, 0, "\t\t - Umbral alcanzado, ejecutando batch MSA");
        Batch_MSA_SQL_Ejecutar($lote_ref);
    }

    $$sql_ref = "";
}

# Ejecuta el lote acumulado y limpia el array
sub Batch_MSA_SQL_Ejecutar {

    my ($lote_ref) = @_;

    my $nombre_modulo = (caller(0))[3];

    my $num_sqls = scalar(@$lote_ref);
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Sentencias en lote: $num_sqls");

    return unless $num_sqls > 0;

    my $sql_total = join("\n", @$lote_ref);

    my ($dbhd);
    $dbhd = ConectarDB->connect_topercable_multi_statement();
    if (not defined $dbhd) {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar BBDD ToperCable. ($DBI::errstr)");
        die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr)\n";
    }

    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Ejecutando UPDATE batch MSA ($num_sqls sentencias)..");
    my $rows = $dbhd->do($sql_total);
    if (!defined $rows) {
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> ERROR ejecutando batch SQL MSA: $DBI::errstr");
        Plogged($log_file, $modo_ejecucion, 3, "\t -> $nombre_modulo -> SQL: $sql_total");
    } else {
        Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> Batch ejecutado OK. Filas afectadas: $rows");
    }

    @$lote_ref = ();
}
#------------------------------------------------------------------


1;      # FIN DEL MODULO
