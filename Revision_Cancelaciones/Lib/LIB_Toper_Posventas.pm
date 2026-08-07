# LIB_Toper_Posventas.pm
#
# Libreria que saca los CDRS del Dataguard de Wholesale para FMS

package LIB_Toper_Posventas;

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
our @EXPORT = qw( get_sf_token Get_SF_Posventas ADD_Alineamiento ADD_MSISDN_To_Alineamiento);

use strict;
use warnings;
use LWP::UserAgent;
use JSON;



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
	$sql = "INSERT INTO topercable.alineamiento_planificado (TIPO, NOMBRE, ESTADO, num_msisdn, creador, prioridad) VALUES ('Cancelaciones', Concat(Date_Sub(Curdate(), interval 1 DAY),' - ', DATE_FORMAT(Date_Sub(Curdate(), interval 1 day), '%W'),' -  Cancelaciones'),0,'$num_msisdn','ToperCable','3') ";
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




sub Get_SF_Posventas {
    #my $token_sf = get_sf_token();
	my $token_sf = Get_Token_SF();
    unless ($token_sf) {
        return { result => 0, SF_Response => "ERROR: token_sf no recibido." };
    }

    my $nombre_modulo = (caller(0))[3];    
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> Inicio ");
    Plogged($log_file, $modo_ejecucion, 0, "\t -> $nombre_modulo -> token_sf: $token_sf ");

    my @all_results;
    my $base_url = "https://masmovil.my.salesforce.com";
    my $urlsf = "/services/data/v51.0/query/?q=";
    my $sql_query = "SELECT Id, MM_Numero_de_Telefono__c FROM orderitem WHERE LastModifiedDate = YESTERDAY AND MM_Estado_BPM__c = 'Cancelled' AND Order.Account.RecordType.Name = 'Residencial' AND vlocity_cmt__ParentItemId__c = '' AND MM_Numero_de_Telefono__c != NULL AND DetalleTipo__c IN ('Cambio de Tarifa','Reemplazo de SIM','Alta bono opcional','Cambio Linea entre bonos') AND vlocity_cmt__AssetId__r.Status = 'Active' LIMIT 20000";
    
    $sql_query =~ s/ /+/g;
    my $next_url = $urlsf . $sql_query;	
	#Plogged($log_file, $modo_ejecucion, 1, "sql_query $sql_query");

    use LWP::UserAgent;
    use JSON;
    my $ua = LWP::UserAgent->new;

    while ($next_url) {
        my $full_url = $base_url . $next_url;
        Plogged($log_file, $modo_ejecucion, 0, "\t -> Llamada: $full_url");

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

        push @all_results, @{$decoded->{records}};

        # Verificar si hay más registros. El campo JSON nextRecordsUrl aparece cuando el resultado supera los 2000 registros, Sustituimos la query original con este valor. Algo concreto de la APi salesforce
        if (exists $decoded->{nextRecordsUrl}) {
            $next_url = $decoded->{nextRecordsUrl};
        } else {
            $next_url = undef;
        }
    }

    # Eliminar duplicados por MM_Numero_de_Telefono__c
    my %visto;
    my @unicos = grep {
        my $tel = $_->{MM_Numero_de_Telefono__c} // '';
        !$visto{$tel}++
    } @all_results;

	# Devolvemos la lsita de MSISDN sin duplicados
    Plogged($log_file, $modo_ejecucion, 1, "\t -> $nombre_modulo -> TotaL msisdn unicos: " . scalar @unicos);
    return {
        result => scalar(@unicos) > 0 ? 1 : 0,
        SF_Registros => \@unicos
    };

}

1;      # FIN DEL MODULO