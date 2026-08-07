# LIB_Toper_RechazosPasarelaCable.pm
#
# Libreria que saca los CDRS del Dataguard de Wholesale para FMS

package LIB_Toper_RechazosPasarelaCable;

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
use LIB_Toper_APPS;	# Libreria comun a Toper, como el Token de Salesforce



# Añadimos nuestras librerias
push (@INC, '.');
use GlobalVariables;
use ConectarDB;
use llogged;

our @ISA    = qw(Exporter);
our @EXPORT = qw( Get_Xena_RechazosPasarelaCable ADD_Alineamiento ADD_MSISDN_To_Alineamiento);

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
	$sql = "INSERT INTO topercable.alineamiento_planificado (TIPO, NOMBRE, ESTADO, num_msisdn, creador, prioridad) VALUES ('Rechazos', Concat(Date_Sub(Curdate(), interval 1 DAY),' - ', DATE_FORMAT(Date_Sub(Curdate(), interval 1 day), '%W'),' -  Rechazos (PasarelaCable)'),0,'$num_msisdn','ToperCable','1') ";
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



sub Get_Xena_RechazosPasarelaCable {
#	Funcion que devuelve una lista con los operadores a Monitorizar.
	
	#	Deaclaramos las variables	
	my ($dbhd,$sthd,$sql);
	my (@MsisdnRechazados,$Msisdnrechazado);	
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];
	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	

	
	#	Conectamos la BBDD Draculon	------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_xena_xprv();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD XNET. \n\nDescripcion del error: ($DBI::errstr)\n\n");
			die "\n\n $nombre_modulo -> ERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	$sthd = $dbhd->prepare("use xnet;");						
	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");	
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
			
	
	Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Sacamos los MSISDN rechazados");
	$sql = "SELECT distinct MSISDN FROM xnet.pv_pasarela_cable_msisdn WHERE TIMESTAMP >= DATE_SUB(NOW(), INTERVAL 1 DAY) and internalCode LIKE 'INS-ERR%';";
	$sthd = $dbhd->prepare($sql);
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
		#	Recorremos las fechas y las gaurdamos en Array para el return
		while(my ($Msisdnrechazado)=$sthd->fetchrow_array()){
			Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Msisdnrechazado: $Msisdnrechazado ");
			push(@MsisdnRechazados,$Msisdnrechazado);
		}		
		
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0,"\n");	
	
	# Devolvemos las operadores
	return(@MsisdnRechazados);	
	#-----------------------------------------------------------------------------------------------------------------------------------------------------------------		
};	# FIN Function


1;      # FIN DEL MODULO