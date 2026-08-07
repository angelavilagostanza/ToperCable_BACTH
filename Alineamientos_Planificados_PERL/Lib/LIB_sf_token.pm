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
our @EXPORT = qw( get_sf_token Get_SF_MSISDN_data Get_SF_MSISDN_Bonos_data );

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
		my $error_message = "Error al consultar el Token. Código de estado: " . $resp->code;
        if ($resp->decoded_content) {
            $error_message .= ", Descripción: " . $resp->decoded_content;
        }
		return $error_message;
    }
}



sub Get_SF_MSISDN_data {
    my ($msisdn, $token) = @_;

    # Verificar parámetros recibidos
    unless ($msisdn && $token) {
        return { result => 0, SF_Response => "ERROR: Parámetros recibidos incorrectos." };
    }

    my $urlsf = "https://masmovil.my.salesforce.com/services/data/v51.0/query/?q=";
    my $qwhere_estado_sf = " and Status <> 'Deleted' ";
    my $sqlsf = "select MM_Numero_de_Telefono__c,status,Product2.name,account.Numero_de_documento__c,Format(account.CO_Codigo_Xena__c) Residencial, Format(vlocity_cmt__BillingAccountId__r.CO_Codigo_Xena__c) Cableoperador, Format(Account.Subtipo__c) marca, vlocity_cmt__RootItemId__c  from asset where MM_Numero_de_Telefono__c = $msisdn $qwhere_estado_sf ";
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
    my $totalSize 			= $data->{totalSize};
	my $SF_Estado 			= $data->{'records'}[0]{'Status'};	
	my $SF_Residencial 		= $data->{'records'}[0]{'Account'}{'Residencial'};
	my $SF_Marca 			= $data->{'records'}[0]{'Account'}{'marca'};
	my $SF_CIF			 	= $data->{'records'}[0]{'Account'}{'Numero_de_documento__c'};
	my $SF_Cableoperador 	= $data->{'records'}[0]{'vlocity_cmt__BillingAccountId__r'}{'Cableoperador'};	
	my $SF_RootItemId		= $data->{'records'}[0]{'vlocity_cmt__RootItemId__c'};
	
	my %parsedData;
    # Aquí continuarías procesando los datos según tu lógica de extracción

	if ($totalSize == 0){
		%parsedData = (
			result => 0,
			SF_msisdn => $msisdn,
			SF_totalsize => $totalSize,
			SF_Estado => "",  
			SF_Cableoperador => "",
			SF_Residencial => "",
			SF_Marca => "",
			SF_CIF => "",
			SF_RootItemId => "",			
			SF_Marca => "",
			SF_Tarifa => "",
			SF_BonoTarifa => "",
			SF_BonoCompartido => "",
			SF_BonosPromociones => "",
			SF_Response => $jsonResponse
		);
	}else{
		# Construir el resultado final
		%parsedData = (
			result => 1,
			SF_msisdn => $msisdn,
			SF_totalsize => $totalSize,
			SF_Estado => $SF_Estado,
			SF_Cableoperador => $SF_Cableoperador,
			SF_Residencial => $SF_Residencial,
			SF_CIF => $SF_CIF,
			SF_RootItemId => $SF_RootItemId,
			SF_Marca => $SF_Marca,
			SF_Tarifa => "",			
			SF_BonoTarifa => "",
			SF_BonoCompartido => "",
			SF_BonosPromociones => "",
			SF_Response => $jsonResponse
		);
	};

    return \%parsedData;
}



sub Get_SF_MSISDN_Bonos_data {
    my ($SF_RootItemId, $token) = @_;

    # Verificar parámetros recibidos
    unless ($SF_RootItemId && $token) {
        return { result => 0, SF_Response => "ERROR: Parámetros recibidos incorrectos." };
    }

    my $urlsf = "https://masmovil.my.salesforce.com/services/data/v51.0/query/?q=";
    my $sqlsf = "select vlocity_cmt__JSONAttribute__c from asset where vlocity_cmt__RootItemId__c = '$SF_RootItemId' and status !='Deleted' and vlocity_cmt__ParentItemId__c != null";
    my $requestUrl = $urlsf . $sqlsf;
    $requestUrl =~ s/ /+/g; # Reemplazar espacios por '+' para formato HTML GET

    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($requestUrl, Authorization => "Bearer $token");

    unless ($response->is_success) {
        #return { result => 0, SF_Response => "Error en la solicitud. Codigo de estado: " . $response->code };
        # ERROR
		my $error_message = "Error al consultar vlocity_cmt__JSONAttribute__c. Codigo de estado: " . $response->code;
        if ($response->decoded_content) {
            $error_message .= ", Descripción: " . $response->decoded_content;
        }
		return $error_message;		
    }

    my $jsonResponse = $response->decoded_content;
    my $data = decode_json($jsonResponse);

    # Procesar la respuesta y extraer los valores deseados
    my $totalSize = $data->{totalSize};
	
	my %parsedData;
	
	if ($totalSize == 0){		
		%parsedData = (
			result => 0,
			SF_totalsize => $totalSize,			
			SF_RootItemId => $SF_RootItemId,	
			SF_JSONAttribute => "",
			SF_Tarifa => "",
			SF_BonoTarifa => "",
			SF_BonoCompartido => "",
			SF_BonosPromociones => "",
			SF_Response => $jsonResponse
		);
	}else{
		# Construir el resultado final
		my $SF_JSONAttribute__c	= $data->{'records'}[0]{'vlocity_cmt__JSONAttribute__c'};
		#$SF_JSONAttribute__c =~ s/\\//g;
		#my $SF_BonoTarifa = $hash{'SF_JSONAttribute__c'};
		my $JSON_SF_JSONAttribute__c		= decode_json($SF_JSONAttribute__c);
		
		my $SF_BonoTarifa	= $JSON_SF_JSONAttribute__c->{'records'}[0]{'attributes'}{'type'};		
			if (defined $SF_BonoTarifa) {
				print "\n\n SF_BonoTarifa: $SF_BonoTarifa \n\n";
			} else {
				print "\n\n SF_BonoTarifa sin valor \n\n";
			};
		
		%parsedData = (
			result => 1,
			SF_totalsize => $totalSize,
			SF_RootItemId => $SF_RootItemId,	
			SF_JSONAttribute => $SF_JSONAttribute__c,
			SF_Tarifa => $SF_BonoTarifa,
			SF_BonoTarifa => "",
			SF_BonoCompartido => "",
			SF_BonosPromociones => "",
			SF_Response => $jsonResponse
		);
		
		
		# Recorremos el JSON Grande parfa evitar realizar multiples llamadas
		
		for my $index (0 .. $totalSize - 1) {
			my $JSON_index = "JSON_($index)";
			print "$JSON_index: \n";
			#print "$data->{'records'}[$index]{'vlocity_cmt__JSONAttribute__c'} \n\n";
			my $JSON_2 = $data->{'records'}[$index]{'vlocity_cmt__JSONAttribute__c'};
			$JSON_2 =~ s/\\//g;
			my $DATA_2 = decode_json($JSON_2);
			#print "JSON_2: $JSON_2 \n\n";
			
			print "$DATA_2->{'attributes'}{'type'} \n\n";
			
			my $tarifa22 = $JSON_2->{'attributes'}{'type'};
			print "tarifa2: $tarifa22";
			
			
		}; # Fin FOR
		
		
		
	};

    return \%parsedData;
}


1;      # FIN DEL MODULO