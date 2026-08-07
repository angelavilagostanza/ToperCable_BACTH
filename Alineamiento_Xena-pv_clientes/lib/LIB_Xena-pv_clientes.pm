# LIB_Xena-pv_clientes.pm
#
# Libreria que saca los CDRS del Dataguard de Wholesale para FMS

package LIB_Xena-pv_clientes;

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
our @EXPORT = qw( Get_Clientes_XPRV Get_Clientes_NFAC );




#	Funcion que devuelve una lista con los operadores a Monitorizar.
sub Get_Clientes_XPRV {	
	
	#	Deaclaramos las variables	
	my ($dbhd,$sthd,$sql);
	my (@OperadoresAMonitoriozar,$CodigoOperador);	
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];
	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	

	
	#	Conectamos la BBDD NFAC	------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_xena_nfac();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD Draculon. \n\nDescripcion del error: ($DBI::errstr)\n\n");
			die "\n\n $nombre_modulo -> ERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	$sthd = $dbhd->prepare("use draculon;");						
	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");	
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	
		
	
	Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Sacamos los Operadores a Monitorizar");	
	$sql = "select codigo_loc from locutorios where estado = 1 and notificar_corte = 1 order by codigo_loc;";
	$sthd = $dbhd->prepare($sql);
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
		#	Recorremos las fechas y las gaurdamos en Array para el return
		while(my ($CodigoOperador)=$sthd->fetchrow_array()){
			#Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> CodigoOperador: $CodigoOperador ");
			push(@OperadoresAMonitoriozar,$CodigoOperador);
		}		
		
		
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0,"\n");	
	
	# Devolvemos las operadores
	return(@OperadoresAMonitoriozar);	
	#-----------------------------------------------------------------------------------------------------------------------------------------------------------------		
};	# FIN Function



#	Funcion que devuelve una lista con los operadores a Monitorizar.
sub Get_Clientes_NFAC {	
	
	#	Deaclaramos las variables	
	my ($dbhd,$sthd,$sql);
	my (@OperadoresAMonitoriozar,$CodigoOperador);	
	
	#	Descripcion del modulo para los mesajes de error
	my $nombre_modulo = (caller(0))[3];
	
	Plogged ($log_file,$modo_ejecucion,0,"\n");
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Inicio ");
	

	
	#	Conectamos la BBDD Draculon	------------------------------------------------------------------------------------------------------------------------------------------------
	$dbhd = ConectarDB->connect_draculon();
		if (not defined $dbhd) {
			Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> ERROR CATASTROFICO. No se pudo conectar la BBDD Draculon. \n\nDescripcion del error: ($DBI::errstr)\n\n");
			die "\n\n $nombre_modulo -> ERROR DE CONEXION BBDD: ($DBI::errstr) \n";
		};	$sthd = $dbhd->prepare("use draculon;");						
	$sthd->execute() or die ("No se pudo ejecutar la consulta. Desc(" . $sthd->errstr . ")");	
	#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	
		
	
	Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> Sacamos los Operadores a Monitorizar");	
	$sql = "select codigo_loc from locutorios where estado = 1 and notificar_corte = 1 order by codigo_loc;";
	#$sql = "select codigo_loc from locutorios where estado = 1 and notificar_corte = 1 and codigo_loc > 1182 order by codigo_loc;";
	#$sql = "select codigo_loc from locutorios where codigo_loc in (1052);";
	$sthd = $dbhd->prepare($sql);
	$sthd->execute() or die ("No se pudo ejecutar la consulta. SQL:($sql)  Desc(" . $sthd->errstr . ")");
	
		#	Recorremos las fechas y las gaurdamos en Array para el return
		while(my ($CodigoOperador)=$sthd->fetchrow_array()){
			#Plogged ($log_file,$modo_ejecucion,0," \t -> $nombre_modulo -> CodigoOperador: $CodigoOperador ");
			push(@OperadoresAMonitoriozar,$CodigoOperador);
		}		
		
		
	
	Plogged ($log_file,$modo_ejecucion,0,"\t -> $nombre_modulo -> Fin");
	Plogged ($log_file,$modo_ejecucion,0,"\n");	
	
	# Devolvemos las operadores
	return(@OperadoresAMonitoriozar);	
	#-----------------------------------------------------------------------------------------------------------------------------------------------------------------		
};	# FIN Function

1;      # FIN DEL MODULO