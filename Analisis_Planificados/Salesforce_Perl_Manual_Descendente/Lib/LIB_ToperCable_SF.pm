# LIB_ToperCable_SF.pm
#
# Libreria de funciones locales

package LIB_ToperCable_SF;

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
use LIB_Toper_APPS;			# Libreria comun a Toper, como el Token de Salesforce


# Añadimos nuestras librerias
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw( Get_Planificados_Pendientes Get_MSISDN_Planificados get_sf_token Get_SF_Activo Get_SF_AssetTarifa Get_SF_AssetBonoCompartido Get_SF_AssetBonoCompartido_BonoDatos Get_SF_AssetPromociones UPDATE_Alineamiento_Detalle UPDATE_Alineamiento_Contador Batch_SQL_Generar Batch_SQL_Ejecutar );

use strict;
use warnings;
use LWP::UserAgent;
use JSON;



#	Devuelve una lista de MSISDN de un Planificado
sub Get_Planificados_Pendientes {	
	
	#	Declaramos las variables Generales
	my ($dbhd,$sthd,$sql);	
	my (@AiTems,$item);
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];
	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	
	#	Conectamos la BBDD ------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_topercable();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD ToperCable. \n\nDescripcion del error: ($DBI::errstr)\n\n");	die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	# $sthd = $dbhd->prepare("use topercable;");	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
	

	Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Sacamos los MSISDN pendientes");
	#$sql = "SELECT id from topercable.alineamiento_planificado WHERE estado < 2 and tipo IN ('Cartera') ORDER BY prioridad, id desc LIMIT 10;";
	$sql = "SELECT id from topercable.alineamiento_planificado WHERE estado < 2 and tipo IN ('Cablero') ORDER BY prioridad, id desc LIMIT 10;";
	#Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> SQL: ($sql) ");
	$sthd = $dbhd->prepare($sql);
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
		#	Recorremos las fechas y las gaurdamos en Array para el return
		while($item=$sthd->fetchrow_array()){
			Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Add al array MSISDN: $item ");
			push(@AiTems,$item);
		};
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0,"\n");	
	
	# Devolvemos el array de Items
	return @AiTems;
	#-----------------------------------------------------------------------------------------------------------------------------------------------------------------		
};	# FIN Function




#	Devuelve una lista de MSISDN de un Planificado
sub Get_MSISDN_Planificados ($) {	
	
	my $planificado_id 	= $_[0];
	
	#	Declaramos las variables Generales
	my ($dbhd,$sthd,$sql);	
	my (@AiTems,$item);
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];
	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	
	#	Conectamos la BBDD ------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_topercable();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD ToperCable. \n\nDescripcion del error: ($DBI::errstr)\n\n");	die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	#$sthd = $dbhd->prepare("use topercable;");	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
	

	Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Sacamos los MSISDN pendientes");
	$sql = "SELECT distinct msisdn FROM alineamiento_planificado_detalle WHERE planificado_id = $planificado_id AND (co_sf='0' OR resi_sf='0' OR cif_sf='0') order by id LIMIT 2000;";
	#Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> SQL: ($sql) ");
	$sthd = $dbhd->prepare($sql);
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
		# #	Recorremos resultado 
		# while($item=$sthd->fetchrow_array()){
			# Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Add al array MSISDN: $item ");
			# push(@AiTems,$item);
		# };
		
		# Recorremos resultado de forma segura, incluso si hay valores 0
		while (defined(my $item = $sthd->fetchrow_array())) {
			Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Add al array MSISDN: $item");
			push(@AiTems, $item);
		}
		
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0,"\n");	
	
	# Devolvemos el array de Items
	return @AiTems;
	#-----------------------------------------------------------------------------------------------------------------------------------------------------------------		
};	# FIN Function



# Get el Activo de Salesforce. Aset cabecera  que lleva el MSISDN
sub Get_SF_Activo {
    my ($token_sf, $msisdn) = @_;

    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: token_sf no recibido." };
    }
    unless ($msisdn) {
        return { result => 0, SF_Response => "ERROR: msisdn no recibido." };
    }

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio ");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> msisdn: $msisdn");

    my $base_url = "https://masmovil.my.salesforce.com";
    my $endpoint = "/services/data/v51.0/query/?q=";

    # Proteger $msisdn con comillas simples para la consulta SOQL
    $msisdn =~ s/'/\\'/g;

    my $sql = <<"SOQL";
SELECT MM_Numero_de_Telefono__c, Status, Product2.Name, Account.Numero_de_documento__c,
Format(Account.CO_Codigo_Xena__c) Residencial,
Format(vlocity_cmt__BillingAccountId__r.CO_Codigo_Xena__c) Cableoperador,
Format(Account.Parent.CreatedDate) CableroFechaAlta,
Format(Account.Subtipo__c) Marca,
vlocity_cmt__RootItemId__c,
Format(Account.Name) ResidencialNombre,
Format(Account.CO_Apellido__c) ResidencialApellido,
Format(Account.Parent.Name) CableroNombre,
Format(Account.Parent.Numero_de_documento__c) CableroNIF,
Format(Account.Parent.CO_facturacion_favorita__r.CO_Codigo_Xena__c) CableroAccount,
Format(vlocity_cmt__ActivationDate__c) FechaAlta,
AccountId,
Format(vlocity_cmt__BillingAccountId__r.ParentId) ParentId,
Format(Account.Fecha_de_alta__c) ResidencialFechaAlta,
Id,
RootOrderItemId__c
FROM Asset
WHERE MM_Numero_de_Telefono__c = $msisdn AND Status <> 'Deleted'
ORDER BY CreatedDate DESC
LIMIT 3
SOQL

    # Eliminar saltos de línea y codificar para URL
    $sql =~ s/\n/ /g;
    $sql =~ s/ +/ /g;
    $sql =~ s/ /+/g;
	#Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> SQLENCODE ($sql) ");

    my $full_url = $base_url . $endpoint . $sql;

    #Plogged($log_file, $modo_ejecucion, 0, "\t -> Llamada: $full_url");

    use LWP::UserAgent;
    use JSON;

    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($full_url, Authorization => "Bearer $token_sf");

    unless ($response->is_success) {
        return { result => 0, SF_Response => "Error HTTP: " . $response->status_line };
    }

    my $decoded;
    eval {
        $decoded = decode_json($response->decoded_content);
    };
    if ($@) {
        return { result => 0, SF_Response => "Error al decodificar JSON: $@" };
    }

    Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> TotalSize: $decoded->{totalSize}");

    return {
        result       => 1,
        SF_Response  => $decoded,
    };
}
#------------------------------------------------------------------



# Get Asset Tarifa
sub Get_SF_AssetTarifa {
    my ($token_sf, $RootItemId) = @_;

    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: token_sf no recibido." };
    }
    unless ($RootItemId) {
        return { result => 0, SF_Response => "ERROR: RootItemId no recibido." };
    }

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio ");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> RootItemId: $RootItemId");

    my $base_url = "https://masmovil.my.salesforce.com";
    my $endpoint = "/services/data/v51.0/query/?q=";

    # Proteger $msisdn con comillas simples para la consulta SOQL
    $RootItemId =~ s/'/\\'/g;

    my $sql = <<"SOQL";
SELECT vlocity_cmt__BillingAccountId__c, vlocity_cmt__JSONAttribute__c 
FROM asset 
WHERE vlocity_cmt__RootItemId__c = '$RootItemId' 
and status !='Deleted' 
and Product2.vlocity_cmt__ObjectTypeId__r.Name in ('Movil_Tarifa_CO','MM_CO_Tarifa') and vlocity_cmt__ParentItemId__c != null 
LIMIT 3
SOQL

    # Eliminar saltos de línea y codificar para URL
    $sql =~ s/\n/ /g;
    $sql =~ s/ +/ /g;
    $sql =~ s/ /+/g;
	#Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> SQLENCODE ($sql) ");

    my $full_url = $base_url . $endpoint . $sql;

    #Plogged($log_file, $modo_ejecucion, 0, "\t -> Llamada: $full_url");

    use LWP::UserAgent;
    use JSON;
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($full_url, Authorization => "Bearer $token_sf");

    unless ($response->is_success) {
        return { result => 0, SF_Response => "Error HTTP: " . $response->status_line };
    }

    my $decoded;
    eval {
        $decoded = decode_json($response->decoded_content);
    };
    if ($@) {
        return { result => 0, SF_Response => "Error al decodificar JSON: $@" };
    }

    Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> TotalSize: $decoded->{totalSize}");

    return {
        result       => 1,
        SF_Response  => $decoded,
    };
}
#------------------------------------------------------------------



# Get Asset BonoCompartido
sub Get_SF_AssetBonoCompartido {
    my ($token_sf, $RootItemId) = @_;

    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: token_sf no recibido." };
    }
    unless ($RootItemId) {
        return { result => 0, SF_Response => "ERROR: RootItemId no recibido." };
    }

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio ");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> RootItemId: $RootItemId");

    my $base_url = "https://masmovil.my.salesforce.com";
    my $endpoint = "/services/data/v51.0/query/?q=";

    # Proteger $msisdn con comillas simples para la consulta SOQL
    $RootItemId =~ s/'/\\'/g;

    my $sql = <<"SOQL";
SELECT MM_BonoDatos_AssetId__c
FROM asset 
WHERE vlocity_cmt__RootItemId__c = '$RootItemId' 
and status !='Deleted' 
and Product2.vlocity_cmt__ObjectTypeId__r.Name = 'Ref_Bono_Movil_CO' 
and vlocity_cmt__ParentItemId__c != null 
LIMIT 3
SOQL

    # Eliminar saltos de línea y codificar para URL
    $sql =~ s/\n/ /g;
    $sql =~ s/ +/ /g;
    $sql =~ s/ /+/g;
	#Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> SQLENCODE ($sql) ");

    my $full_url = $base_url . $endpoint . $sql;

    #Plogged($log_file, $modo_ejecucion, 0, "\t -> Llamada: $full_url");

    use LWP::UserAgent;
    use JSON;
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($full_url, Authorization => "Bearer $token_sf");

    unless ($response->is_success) {
        return { result => 0, SF_Response => "Error HTTP: " . $response->status_line };
    }

    my $decoded;
    eval {
        $decoded = decode_json($response->decoded_content);
    };
    if ($@) {
        return { result => 0, SF_Response => "Error al decodificar JSON: $@" };
    }

    Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> TotalSize: $decoded->{totalSize}");

    return {
        result       => 1,
        SF_Response  => $decoded,
    };
}
#------------------------------------------------------------------


# Get Asset BonoCompartido (Segunda Parte)
sub Get_SF_AssetBonoCompartido_BonoDatos {
    my ($token_sf, $BonoDatos_AssetId) = @_;

    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: token_sf no recibido." };
    }
    unless ($BonoDatos_AssetId) {
        return { result => 0, SF_Response => "ERROR: BonoDatos_AssetId no recibido." };
    }

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio ");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> BonoDatos_AssetId: $BonoDatos_AssetId");

    my $base_url = "https://masmovil.my.salesforce.com";
    my $endpoint = "/services/data/v51.0/query/?q=";

    # Proteger $msisdn con comillas simples para la consulta SOQL
    $BonoDatos_AssetId =~ s/'/\\'/g;

    my $sql = <<"SOQL";
SELECT vlocity_cmt__BillingAccountId__r.CO_Codigo_Xena__c, vlocity_cmt__JSONAttribute__c
FROM asset 
WHERE vlocity_cmt__ParentItemId__c = '$BonoDatos_AssetId' 
and status !='Deleted' 
LIMIT 3
SOQL

    # Eliminar saltos de línea y codificar para URL
    $sql =~ s/\n/ /g;
    $sql =~ s/ +/ /g;
    $sql =~ s/ /+/g;
	Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> SQLENCODE ($sql) ");

    my $full_url = $base_url . $endpoint . $sql;

    #Plogged($log_file, $modo_ejecucion, 0, "\t -> Llamada: $full_url");

    use LWP::UserAgent;
    use JSON;
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($full_url, Authorization => "Bearer $token_sf");

    unless ($response->is_success) {
        return { result => 0, SF_Response => "Error HTTP: " . $response->status_line };
    }

    my $decoded;
    eval {
        $decoded = decode_json($response->decoded_content);
    };
    if ($@) {
        return { result => 0, SF_Response => "Error al decodificar JSON: $@" };
    }

    Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> TotalSize: $decoded->{totalSize}");

    return {
        result       => 1,
        SF_Response  => $decoded,
    };
}
#------------------------------------------------------------------




# Get Asset Promociones
sub Get_SF_AssetPromociones {
    my ($token_sf, $RootItemId) = @_;

    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: token_sf no recibido." };
    }
    unless ($RootItemId) {
        return { result => 0, SF_Response => "ERROR: RootItemId no recibido." };
    }

    my $nombre_modulo = (caller(0))[3];
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio ");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> RootItemId: $RootItemId");

    my $base_url = "https://masmovil.my.salesforce.com";
    my $endpoint = "/services/data/v51.0/query/?q=";

    # Proteger $msisdn con comillas simples para la consulta SOQL
    $RootItemId =~ s/'/\\'/g;

    my $sql = <<"SOQL";
SELECT vlocity_cmt__JSONAttribute__c
FROM asset 
WHERE vlocity_cmt__RootItemId__c = '$RootItemId' 
and status !='Deleted' 
and Product2.vlocity_cmt__ObjectTypeId__r.Name = 'Promociones_CO' 
and vlocity_cmt__ParentItemId__c != null 
order by id
LIMIT 10
SOQL

    # Eliminar saltos de línea y codificar para URL
    $sql =~ s/\n/ /g;
    $sql =~ s/ +/ /g;
    $sql =~ s/ /+/g;
	#Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> SQLENCODE ($sql) ");

    my $full_url = $base_url . $endpoint . $sql;

    #Plogged($log_file, $modo_ejecucion, 0, "\t -> Llamada: $full_url");

    use LWP::UserAgent;
    use JSON;
    my $ua = LWP::UserAgent->new;
    my $response = $ua->get($full_url, Authorization => "Bearer $token_sf");

    unless ($response->is_success) {
        return { result => 0, SF_Response => "Error HTTP: " . $response->status_line };
    }

    my $decoded;
    eval {
        $decoded = decode_json($response->decoded_content);
    };
    if ($@) {
        return { result => 0, SF_Response => "Error al decodificar JSON: $@" };
    }

    Plogged($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> TotalSize: $decoded->{totalSize}");

    return {
        result       => 1,
        SF_Response  => $decoded,
    };
}
#------------------------------------------------------------------


sub UPDATE_Alineamiento_Detalle {
	#	Funcion que guarda en una tabla el registro del proceso del cliente
	my ($msisdn,$alineamiento_id,$sf_co,$sf_resi,$sf_nif,$sf_tarifa,$sf_bonoco,$sf_promos) = @_;	
	#Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> msisdn: $msisdn  alineamiento_id: $alineamiento_id");
	
	
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
		};	#$sthd = $dbhd->prepare("use topercable;");	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
			
	
	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Actualizando Datos SF ID: $alineamiento_id MSISDN: $msisdn .. ");	
	$sql = "UPDATE topercable.alineamiento_planificado_detalle SET co_sf = '$sf_co', resi_sf = '$sf_resi', cif_sf = '$sf_nif', tarifa_sf = '$sf_tarifa', bc_sf = '$sf_bonoco', promo_sf = '$sf_promos' WHERE planificado_id = $alineamiento_id and msisdn = '$msisdn';";
	$sthd = $dbhd->prepare($sql);	
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
	#Plogged ($log_file,$modo_ejecucion,1,"$sql");
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0," ");
	
	return 1;
};	# FIN Function


sub UPDATE_Alineamiento_Contador {
	#	Funcion que guarda en una tabla el registro del proceso del cliente
	my ($alineamiento_id) = @_;	
	#Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> alineamiento_id: $alineamiento_id");
	
	
	    # Verificar parámetros recibidos
    unless ($alineamiento_id) {
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
		};	#$sthd = $dbhd->prepare("use topercable;");	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
			
	
	Plogged ($log_file,$modo_ejecucion,0,"\t\t -> $nombre_modulo -> Actualizando contador Planificado ID: $alineamiento_id .. ");	
	$sql = "UPDATE topercable.alineamiento_planificado SET chk_salesforce = (SELECT SUM(If(tarifa_sf = '0',0,1)) PROCESADOS FROM topercable.alineamiento_planificado_detalle WHERE planificado_id = $alineamiento_id ) WHERE ID = $alineamiento_id;";
	$sthd = $dbhd->prepare($sql);	
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");	
	#Plogged ($log_file,$modo_ejecucion,1,"$sql");
	
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0," ");
	
	return 1;
};	# FIN Function



# Batch apra ejecutar los Updates de 100 en 100 en lugar de uno en uno ------------------------------
# Función que gestiona la ejecución por lotes
sub Batch_SQL_Generar {
    my ($sql_ref, $lote_ref, $batch_size) = @_;

    push @$lote_ref, $$sql_ref;

	Plogged ($log_file,$modo_ejecucion,0,"\t\t - Generando SQL update");
    if (scalar(@$lote_ref) >= $batch_size) {
		Plogged ($log_file,$modo_ejecucion,0,"\t\t - Ejecutando SQL update");
        Batch_SQL_Ejecutar($lote_ref);
    }

    # Reinicia la SQL actual
    $$sql_ref = "";
}

# Ejecuta el lote completo de SQL y limpia el array
sub Batch_SQL_Ejecutar {
    my ($lote_ref) = @_;


	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");

    my $sql_total = join("\n", @$lote_ref);

	#	Conectamos la BBDD ------------------------------------------------------------------------------------------------------------------------------------------------
	my ($dbhd);
	$dbhd = ConectarDB->connect_topercable_multi_statement();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,1," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD ToperCable. \n\nDescripcion del error: ($DBI::errstr)\n\n");	die "\n\nERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	
    
    if ($sql_total ne "") {
		Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo *-> Ejecutaado UPDATE SQL.. ");
        $dbhd->do($sql_total) or warn "Error en batch SQL: $DBI::errstr";
    }

    @$lote_ref = ();  # limpiar lote
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0," ");	
}
#---------------------------------------------------------------------------------------------------



1;      # FIN DEL MODULO