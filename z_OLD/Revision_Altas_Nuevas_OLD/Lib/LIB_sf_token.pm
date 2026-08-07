# LIB_sf_token.pm
#
# Libreria que saca los CDRS del Dataguard de Wholesale para FMS

package LIB_sf_token;

use utf8;
use strict;
use warnings;
use DBI;
use Exporter;
use Archive::Extract;
use File::Copy qw(move mv);
use Data::Types qw(:all);		# Para conocer el tipo de dato almacenado
use Switch;
use POSIX "strftime";
use DateTime::Locale;
use Time::Local;
use Data::Dumper qw(Dumper);
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);



# Añadimos nuestras librerias
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw( get_sf_token Get_SF_AltasPortin_Nuevas ADD_Alineamiento ADD_MSISDN_To_Alineamiento);

use strict;
use warnings;
use LWP::UserAgent;
use JSON;

sub get_sf_token {
    # URL del punto final de la API
    my $url = "https://masmovil.my.site.com/cableOperadores/services/apexrest/api/v2/login-api?domain=login";

    # Cuerpo de la solicitud
    my $request_body = '{"username": "operacionesitn2@masmovil.com", "password": "6oCmtB3L5o"}';

    # Crea un objeto LWP::UserAgent
    my $ua = LWP::UserAgent->new;

    # Configura la solicitud POST
    my $req = HTTP::Request->new(POST => $url);
    $req->header('Content-Type' => 'application/json');
    $req->content($request_body);

    # Envía la solicitud POST
    my $resp = $ua->request($req);

    # Verifica el código de estado de la respuesta
    if ($resp->is_success) {
        # OK
        my $response_json = decode_json($resp->decoded_content);

        # Extraemos el token buscando la posición de sessionId
        my $session_id = $response_json->{'sessionId'};

        return $session_id;
    } else {
        # ERROR
		my $error_message = "Error al consultar el Token. Codigo de estado: " . $resp->code;
        if ($resp->decoded_content) {
            $error_message .= ", Descripción: " . $resp->decoded_content;
        }
		return $error_message;
    }
}





sub Get_SF_AltasPortin_Nuevas {
    my ($token) = @_;

    # Verificar parámetros recibidos
    unless ($token) {
        return { result => 0, SF_Response => "ERROR: Parámetros recibidos incorrectos." };
    }

    my $urlsf = "https://masmovil.my.salesforce.com/services/data/v51.0/query/?q=";
	my $sqlsf = "select MM_Numero_de_Telefono__c from orderitem where LastModifiedDate = YESTERDAY and MM_Estado_BPM__c = 'Completed' and Order.Account.RecordType.Name = 'Residencial' and vlocity_cmt__ParentItemId__c = '' and MM_Numero_de_Telefono__c != NULL and MM_Asset_generado__c = True and DetalleTipo__c IN ('Portabilidad Postpago','Portabilidad Prepago','Alta nueva') Limit 2001";
	
	
	
    my $requestUrl = $urlsf . $sqlsf;
    $requestUrl =~ s/ /+/g; # Reemplazar espacios por '+' para formato HTML GET

    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($requestUrl, Authorization => "Bearer $token");

    unless ($response->is_success) {
        return { result => 0, SF_Response => "Error en la solicitud. Código de estado: " . $response->code };
    }

    my $jsonResponse = $response->decoded_content;
    my $data = decode_json($jsonResponse);

    # Procesar la respuesta y extraer los valores deseados
    my $totalSize = $data->{totalSize};
	Plogged ($log_file,$modo_ejecucion,1,"- totalSize: $totalSize");

    my @parsedData;
    foreach my $record (@{ $data->{records} }) {
        push @parsedData, {
			SF_Numero_de_Telefono => $record->{MM_Numero_de_Telefono__c}
            # Agregar otros campos si es necesario
        };		
		#Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo Altas nuevas de ayer..");
    }

    #return \@parsedData;   
	return { result => 1, SF_Registros => \@parsedData };
}





sub ADD_Alineamiento {
	#	Funcion que guarda en una tabla el registro del proceso del cliente
	 my ($num_msisdn) = @_;
	
	#	Declaramos las variables	
	my ($dbhd,$sthd,$sql,$ary);
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	
	
	
	#	Conectamos la BBDD ------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_topercable();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD ToperCable. \n\nDescripcion del error: ($DBI::errstr)\n\n");	die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	$sthd = $dbhd->prepare("use topercable;");	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
			
	
	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Añadiendo alineamiento.. ");	
	$sql = "INSERT INTO topercable.alineamiento_planificado (TIPO, NOMBRE, ESTADO, num_msisdn) VALUES ('SF Altas Nuevas', Concat(Date_Sub(Curdate(), interval 1 day),'  - Altas nuevas'),0,'$num_msisdn') ";
	$sthd = $dbhd->prepare($sql);	
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	

	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Añadiendo alineamiento.. ");	
	$sql = "SELECT LAST_INSERT_ID() AS LastID";
	$sthd = $dbhd->prepare($sql);	
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");	
	$ary = $sthd->fetchrow_hashref();	
	my $alineamiento_id	= $ary->{"LastID"}; 	
	
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0," ");
	
	return $alineamiento_id;
};	# FIN Function


sub ADD_MSISDN_To_Alineamiento {
	#	Funcion que guarda en una tabla el registro del proceso del cliente
	 my ($msisdn,$alineamiento_id) = @_;
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> msisdn: $msisdn ");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> alineamiento_id: $alineamiento_id ");
	
	
	    # Verificar parámetros recibidos
    unless ($msisdn && $alineamiento_id) {
        return { result => 0, SF_Response => "ERROR: Parámetros recibidos incorrectos." };
    }
	
	#	Declaramos las variables	
	my ($dbhd,$sthd,$sql,$ary);
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	
	
	
	#	Conectamos la BBDD ------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_topercable();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD ToperCable. \n\nDescripcion del error: ($DBI::errstr)\n\n");	die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	$sthd = $dbhd->prepare("use topercable;");	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
			
	
	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Añadiendo alineamiento.. ");	
	$sql = "INSERT IGNORE INTO topercable.alineamiento_planificado_detalle (`planificado_id`, `msisdn`) VALUES ('$alineamiento_id','$msisdn');";
	$sthd = $dbhd->prepare($sql);	
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
	#Plogged ($log_file,$modo_ejecucion,1,"$sql");
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0," ");
	
	return 1;
};	# FIN Function



1;      # FIN DEL MODULO