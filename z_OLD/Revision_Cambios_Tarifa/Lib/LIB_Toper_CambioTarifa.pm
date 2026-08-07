# LIB_Toper_CambioTarifa.pm
#
# Libreria que saca los CDRS del Dataguard de Wholesale para FMS

package LIB_Toper_CambioTarifa;

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
our @EXPORT = qw( get_sf_token Get_SF_Cambio_Tarifa ADD_Alineamiento ADD_MSISDN_To_Alineamiento);

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





sub Get_SF_Cambio_Tarifa {
	
	my $token_sf = get_sf_token();

    # Verificar parámetros recibidos
    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: Parámetros recibidos incorrectos." };
    }
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> token_sf: $token_sf ");
	
	my $num_queries = 0;
	my $NumRegistros = 0;
	my $sqllimit = 2000;
	my $offset = 2000;
	my @all_results;
	

	# Obtenemos el numero de registros a devolver para calcular el OFFSET y las tandas de 2k a obtener
    my $urlsf0 = "https://masmovil.my.salesforce.com/services/data/v51.0/query/?q=";
	my $sqlsf0 = "select Format(Count(id))Num from orderitem where LastModifiedDate = YESTERDAY and MM_Estado_BPM__c = 'Completed' and Order.Account.RecordType.Name = 'Residencial' and vlocity_cmt__ParentItemId__c = '' and MM_Numero_de_Telefono__c != NULL and MM_Asset_generado__c = True and DetalleTipo__c = 'Cambio de Tarifa' and vlocity_cmt__AssetId__r.Status  = 'Active'";
    my $requestUrl0 = $urlsf0 . $sqlsf0;
    $requestUrl0 =~ s/ /+/g; # Reemplazar espacios por '+' para formato HTML GET

    my $ua0 = LWP::UserAgent->new;
    my $response0 = $ua0->get($requestUrl0, Authorization => "Bearer $token_sf");

    unless ($response0->is_success) {
        return { result => 0, SF_Response => "Error en la solicitud. Código de estado: " . $response0->code };
    }
	use JSON;
	my $decoded_json = decode_json($response0->decoded_content);
	# Verificar si totalSize es mayor que 0
	if ($decoded_json->{totalSize} > 0) {
		$NumRegistros = $decoded_json->{records}[0]{Num};
	} else {
		$NumRegistros = 0;
	};
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Total registros: $NumRegistros");	
	
	
	# Calcular el número de consultas necesarias
	if ( $NumRegistros > 0 ) {
		$num_queries = int($NumRegistros / $sqllimit);
		$num_queries++ if $NumRegistros % $sqllimit != 0;
	}else{
		$num_queries = 0;
	};	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Bucles: $num_queries");
	#----------------------------------------------------------------------------------------------------------
	
	
	# Extraemos regsutros
	if ($num_queries > 0) {		
		for (my $i = 0; $i <= $num_queries; $i++) {
			
			my $sqloffset = $i * $offset;
			Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> I: $i");
			Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Offset: $sqloffset");

			# Extraemos las andas de 2000 
			my @query_results = Get_SF_Cambio_Tarifa_mock($sqllimit, $sqloffset, $token_sf);
			
			# Combinar los resultados de cada consulta en @all_results
			push @all_results, @query_results;
			
		}; # Fin For num_querys

		
		return { result => 1, SF_Registros => \@all_results };
	}else{
		
		return { result => 0, SF_Registros => \@all_results };
	}

    #return \@parsedData;  	
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
	
	
	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Cambiando idioma a es_ES.. ");	
	$sql = "SET lc_time_names = 'es_ES'";
	$sthd = $dbhd->prepare($sql);	
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");	

	
	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Añadiendo alineamiento.. ");	
	$sql = "INSERT INTO topercable.alineamiento_planificado (TIPO, NOMBRE, ESTADO, num_msisdn) VALUES ('Cambios de Tarifa', Concat(Date_Sub(Curdate(), interval 1 DAY),' - ', DATE_FORMAT(Date_Sub(Curdate(), interval 1 day), '%W'),' -  Cambios tarifa'),0,'$num_msisdn') ";
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



# Funcion mock para extraer los registros de una consulta SF  con LIMIT y OFFSET
sub Get_SF_Cambio_Tarifa_mock {
    my ($limit, $offset, $token_sf) = @_;
    my @results;	
	#my $token_sf = get_sf_token();
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");		
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> limit: $limit ");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> offset: $offset ");
	#Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> token_sf: $token_sf ");

		
		my $urlsf = "https://masmovil.my.salesforce.com/services/data/v51.0/query/?q=";
		my $sqlsf = "SELECT MM_Numero_de_Telefono__c FROM orderitem WHERE LastModifiedDate = YESTERDAY and MM_Estado_BPM__c = 'Completed' and Order.Account.RecordType.Name = 'Residencial' and vlocity_cmt__ParentItemId__c = '' and MM_Numero_de_Telefono__c != NULL and MM_Asset_generado__c = True and vlocity_cmt__AssetId__r.Status  = 'Active' and DetalleTipo__c = 'Cambio de Tarifa' LIMIT $limit  OFFSET $offset";
		my $requestUrl = $urlsf . $sqlsf;
		$requestUrl =~ s/ /+/g; # Reemplazar espacios por '+' para formato HTML GET
		my $ua = LWP::UserAgent->new;
		my $response = $ua->get($requestUrl, Authorization => "Bearer $token_sf");

		unless ($response->is_success) {
			return { result => 0, SF_Response => "Error en la solicitud. Código de estado: " . $response->code };
		}

		my $jsonResponse = $response->decoded_content;
		my $data = decode_json($jsonResponse);

		# Procesar la respuesta y extraer los valores deseados
		my $totalSize = $data->{totalSize};
		Plogged ($log_file,$modo_ejecucion,1,"-> $nombre_modulo -> totalSize: $totalSize");


		foreach my $record (@{ $data->{records} }) {
			push @results, {
				SF_Numero_de_Telefono => $record->{MM_Numero_de_Telefono__c}
				# Agregar otros campos si es necesario
			};
		}; # Fin FOR Extracion regsitros
    
	
    return @results;
}; # Fin funcion

1;      # FIN DEL MODULO