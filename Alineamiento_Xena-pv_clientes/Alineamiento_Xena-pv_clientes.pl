#!C:\Perl64\bin\perl.exe

# Descripcion del Script	####################################################
#
#	Script que Envia ficheros con CDRS, cada 10 minutos, a FMS apra analisis de fraude en Roaming
#
################################################################################

use utf8;
use warnings;
use strict;
use DBI;
use Switch;
use POSIX "strftime";
use File::Copy;
use DateTime::Locale;
use Time::Local;
use Exporter;
use Number::Format;
use Net::FTP;
use File::Copy qw(move mv);
use Data::Dumper qw(Dumper);
use Archive::Extract;

 
# Librerias 
use lib 'D:\Intranet\Perl\comun\lib';
use lib '.\lib';
use GlobalVariables;
use llogged;
use ConectarDB;
use EmailsComerciales;
use LIB_Draculon_Parametros;
use LIB_Global_Fichero;


# Librerias Locales al proceso
use LIB_cdrs_fms;
use LIB_WinSCP;
require "Config.pl";		# Importamos variables de configuraciones



#**************************************************************************************************************************
#	Cabecera de Script
Script_Cabecera;


#-------------------------------------------------------------------------------------
#	Variables globales de GlobalVariables.pm
our $email_desarrollo;
our $email_root_procesos;
our $email_JIRA_PSD;
#-------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------
#	Variables del archivo Config.pl
our $ruta_directorio_enviados;
our $ruta_directorio;
our $FMS_directorio;
our $num_max_registros;
#-------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------
#	Variables locales
#-------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------
# Descomentar para DEBUG
# Esta variable machaca la de GlobalVariables 0:DEBUG  1:PRODUCCION				Tipo mensaje: 0:DEBUG	1:INFO	2:OK	3:ERROR
$modo_ejecucion = 1;
if ($modo_ejecucion == 0){
	$email_sistemas 	= $email_desarrollo;
	$email_JIRA_PSD 	= $email_desarrollo;
};
$email_sistemas 	= $email_desarrollo;

#**************************************************************************************************************************
#  Empezamos

# FICHERO PID. Creamos el fichero PID para evitar solpamiento en ejecuciones
FileExists($0,0);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
#------------------------------------------------------------------

Plogged ($log_file,$modo_ejecucion,1,"\n\n");
Plogged ($log_file,$modo_ejecucion,1," ");




Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo el ultimo ID_LLAMADA enviado a FMS..");
	my $ultimo_id_llamada_enviado = GET_Ultimo_ID_LLAMADA_enviado;
		if ($ultimo_id_llamada_enviado == 1 ) {
			Plogged ($log_file,$modo_ejecucion,3,"ERROR ultimo_id_llamada_enviado incoherente ($ultimo_id_llamada_enviado)");
			Plogged_Mail($email_root_procesos,$log_file,"Envio CDRS FMS. Ultimo ID_LLAMADA incoherente o fuera de rango ($ultimo_id_llamada_enviado)","El proceso de envio a FMS tiene un ID_LLAMADA Incoherente ($ultimo_id_llamada_enviado).<br><br><br><br>Debe inicializarse la tabla con un ID adecuado<br>");
			FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
			exit 1;
		};
	my $fecha_ultimo_id_llamada_enviado = GET_FECHA_ID_LLAMADA($ultimo_id_llamada_enviado);
	Plogged ($log_file,$modo_ejecucion,1,"\t ultimo_id_llamada_enviado: $ultimo_id_llamada_enviado - $fecha_ultimo_id_llamada_enviado");



Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo el ultimo ID_LLAMADA en curso..");
	my $ultimo_id_llamada_curso = GET_Ultimo_ID_LLAMADA_curso;
		if ($ultimo_id_llamada_curso == 1 ) {
			Plogged ($log_file,$modo_ejecucion,3,"ERROR ultimo_id_llamada_curso incoherente ($ultimo_id_llamada_curso)");
			Plogged_Mail($email_root_procesos,$log_file,"ENvio CDRS FMS. Ultimo ID_LLAMADA incoherente ($ultimo_id_llamada_curso)","El proceso de envio a FMS tiene un ID_LLAMADA Incoherente ($ultimo_id_llamada_enviado).<br><br>");
			FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
			exit 1;
		};
	my $fecha_ultimo_id_llamada_curso = GET_FECHA_ID_LLAMADA($ultimo_id_llamada_curso);
	Plogged ($log_file,$modo_ejecucion,1,"\t ultimo_id_llamada_curso: $ultimo_id_llamada_curso - $fecha_ultimo_id_llamada_curso");


# Controlamos el volumen de la extraccion, maximo 1.000.000 de registros por tanda. Si no se controla podriamos estar extrayendo varias Gigas de golpe y fallaria.
Plogged ($log_file,$modo_ejecucion,1,"- Comprobando ID_LLAMADA..");
my $diff=$ultimo_id_llamada_curso-$ultimo_id_llamada_enviado;
	if($diff > $num_max_registros){
		$ultimo_id_llamada_curso = $ultimo_id_llamada_enviado+$num_max_registros;
		Plogged ($log_file,$modo_ejecucion,1,"\t Demasiados registros ($diff). Modificamos ultimo_id_llamada_curso: $ultimo_id_llamada_curso");
	}else{
		Plogged ($log_file,$modo_ejecucion,1,"\t OK Diferencia ($diff)");
	};
#----------------------------------------------------------------------------------------------------



Plogged ($log_file,$modo_ejecucion,1,"- Nombre de fichero CSV..");
my $fichero_csv = GET_Nombre_Fichero;
Plogged ($log_file,$modo_ejecucion,1,"\t $ruta_directorio\\$fichero_csv");



Plogged ($log_file,$modo_ejecucion,1,"- Exportando CDRS..");
my $check_export_fichero = Export_CDRS_Fichero($ultimo_id_llamada_enviado,$ultimo_id_llamada_curso,$ruta_directorio,$fichero_csv);
	if($check_export_fichero == 1){
		Plogged ($log_file,$modo_ejecucion,3,"\t ERROR check_export_fichero ($check_export_fichero)");
		Plogged_Mail($email_root_procesos,$log_file,"Envio CDRS FMS. No se exporto el fichero","El proceso de envio a FMS no pudo exportar el fichero de CDRS<br>");
		FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
		exit 1;		
	}else{
		Plogged ($log_file,$modo_ejecucion,1,"\t OK check_export_fichero ($check_export_fichero) \n");
	};
#----------------------------------------------------------------------------------------------------



#	Actualizamos el ultimo ID_LLAMADA procesado para continuar desde ahi en la proxima ejecucion
Plogged ($log_file,$modo_ejecucion,1,"- Actualizando ultimo ID_LLAMADA enviado..");
UPDATE_Ultimo_ID_LLAMADA_enviado($ultimo_id_llamada_curso,$ruta_directorio,$fichero_csv);
Plogged ($log_file,$modo_ejecucion,1,"\n\n");



#	Subimos CDRS a FMS	----------------------------------------------------------------------------
Plogged ($log_file,$modo_ejecucion,1,"- Enviando CDRS a FMS por SFTP..");
 my $file_origen 	= $ruta_directorio."\\".$fichero_csv;
 my $file_destino 	= $FMS_directorio."/".$fichero_csv;
 Plogged ($log_file,$modo_ejecucion,1,"\t Fichero Origen: $file_origen");
 Plogged ($log_file,$modo_ejecucion,1,"\t Fichero Destino: $file_destino");
 my $envio_fms = WinSCP_Upload ($file_origen,$file_destino);	
	if ($envio_fms == 1 ) {
		Plogged ($log_file,$modo_ejecucion,3,"ERROR envio SCP a FMS erroneo");
		Plogged_Mail($email_root_procesos,$log_file,"ERROR Envio CDRS FMS SCP fallo","El proceso SCP de envio a FMS fallo.<br><br>file_origen:  ($file_origen)<br>file_destino: ($file_destino)<br><br><br><br>Debe inicializarse la tabla con un ID adecuado<br>");
		FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
		exit 1;
	}else{
		Plogged ($log_file,$modo_ejecucion,1,"- Comprimimos y almacenamos el fichero enviado..");
		my $fichero_comprimido = Comprimir_CSV_A_ZIP ($file_origen);
		if ($fichero_comprimido == 1 ) {
			Plogged ($log_file,$modo_ejecucion,3,"ERROR CDRS FMS compresion de archivo");
			Plogged_Mail($email_root_procesos,$log_file,"ERROR compresion CDRS FMS SCP","El proceso de compresion de fiehros FMS fallo.<br><br>");
		}else{
			Plogged ($log_file,$modo_ejecucion,1,"\t ..OK \n"); 
			
			my $fichero_zip = $fichero_csv;		$fichero_zip =~ s/.csv/.zip/;
			my $file_origen_gz	= $ruta_directorio."\\".$fichero_zip;
			my $file_destino_gz	= $ruta_directorio_enviados."\\".$fichero_zip;
			Plogged ($log_file,$modo_ejecucion,0,"\t file_origen_gz: $file_origen_gz \n");
			Plogged ($log_file,$modo_ejecucion,0,"\t file_destino_gz: $file_destino_gz \n");
			move ($file_origen_gz,$file_destino_gz);
		};
		
	};
#-------------------------------------------------------------------------------------------------------



# Purgamos ficheros CDRS enviados antiguos 
Plogged ($log_file,$modo_ejecucion,1,"- Purgando CDRS enviados hace 7 dias..");
Purgado_Ficheros_Enviados (7,$ruta_directorio_enviados);



Plogged ($log_file,$modo_ejecucion,1,"\n\n");
#-----------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Buscamos errores en LOG para notificar a ROOT
Buscar_Error_En_LOG($modo_ejecucion,$log_file,$email_desarrollo,$email_desarrollo);

#	FICHERO PID. Borramos el fichero PID para liberar la ejecucion.
FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)

#	Purgamos los LOG
Script_Purgado_Logs(10);

#	Pie del Script
Script_Pie;

# Salimos con OK
exit 0;