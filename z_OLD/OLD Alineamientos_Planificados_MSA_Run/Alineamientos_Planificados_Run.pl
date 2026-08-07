#!C:Perl\bin\perl.exe -w
#use strict;
use DBI;
use Switch;
use POSIX "strftime";
use utf8;
use warnings;
use strict;
use Time::Local;
use File::Copy;
use DateTime::Locale;
use File::Path qw(make_path);


# Añadimos nuestras librerias
use lib 'D:\Intranet\Perl\comun\lib';
use GlobalVariables;
use llogged;

#**************************************************************************************************************************
#  Script que lanza el analisis de alneamiento planificado en Topercable
#  Se ejecuta todos los dias a cada 2 horas
#

#**************************************************************************************************************************
#	Cabecera de Script
Script_Cabecera;


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Email Notificador
our $email_sistemas;
our $email_direccion_whs;

my $texto_asunto;
my $texto_mail;
my $texto_mail_comercial;

$modo_ejecucion				= 1; # 0= produccion   1=Debugger
my $dir_principal			= "D:\\Intranet\\Script\\ToperCable\\Alineamientos_Planificados_MSA_Run\\LOGS\\";
my $dir_rot 				= strftime("%Y-%m-%d_%H%M%S",localtime(time()));
my $directorio_log			= $dir_principal . $dir_rot;
my $archivo_log_proceso 	= $directorio_log . ".log";
my $archivo_log_proceso_e	= $dir_principal . "Alineamientos_Planificados_Run_" . strftime("%Y-%m-%d_%H.%M.%S",localtime(time())) . "_Lanzador.log";
#-----------------------------------------------------------------------------------------------------------------------------------------------------------------

$email_sistemas = "angel\.avila\@masmovil.com";;
$email_direccion_whs 	= $email_sistemas;


#**************************************************************************************************************************
# Empezamos
# FICHERO PID. Creamos el fichero PID para evitar solpamiento en ejecuciones
FileExists($0,0);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
#------------------------------------------------------------------



Plogged ($log_file,$modo_ejecucion,1,"- Directorio LOGS para WGet: $directorio_log");
eval {
    make_path($directorio_log, { mode => 0755 });
};
	if ($@) {
		my $error_message = $@;
		Plogged($log_file, $modo_ejecucion, 1, "ERROR. No se creo el directorio LOGS ($directorio_log). Error: $error_message");
		
		my $texto_asunto = "ERROR. La creacion del directorio LOG fue fallida.";
		my $texto_mail = "<b><font color=red>Error del JOB Alineamientos Planificados Cablemovil</b><br><br>No se pudo crear el directorio de LOGS ($directorio_log).<br><br>Error: $error_message.</b></font>";
		$texto_mail .= "<br><br><font color=black>ToperCable NO puede continuar con el proceso.<br><br><b>.: ToperCable :.<br>Grupo MASMOVIL</b></font>";
		Plogged_Mail($email_sistemas, $log_file, $texto_asunto, $texto_mail);
		Plogged($log_file, $modo_ejecucion, 3, "ERROR. No se creo el directorio LOGS ($directorio_log) Fallida: $error_message");
		
		exit 1;
	} else {
		Plogged($log_file, $modo_ejecucion, 0, "OK. Creacion del directorio correcta");
	}
Plogged ($log_file,$modo_ejecucion,1," ");




Plogged ($log_file,$modo_ejecucion,1,"- Lanzamos CURL de analisis Alineamiento Planificado MSA");
	
	#	Ejecutamos la Notificacion (WGET)	
	$salida_system = system("\"C:\\wget\\wget.exe\" --verbose --user=topercable_runmsa --password=T0p3rC4bl3 --no-check-certificate --secure-protocol=TLSv1_2 -c -E -P$directorio_log  http://10.27.47.123:84/Alineamiento_planificado/alineamiento_planificado_run_msa.asp");
	#$salida_system = 0;
	Plogged ($log_file,$modo_ejecucion,1,"\n\n\n");
	Plogged ($log_file,$modo_ejecucion,1,"Salida: $salida_system \n\n\n");

	
		#	Comprobamos si la salida del Comando Fue correcta.	-----------------------------------------------
		Plogged ($log_file,$modo_ejecucion,1,"Comprobamos ejecucion Wget Paso 2..");
		if ($salida_system == 0 || $salida_system == 2048){
			Plogged ($log_file,$modo_ejecucion,1,"OK. Wget Salesforce correcto. Salida: $salida_system \n\n\n");
			
			$texto_asunto = "OK. Analsis alineamiento planificado se realizo correctamente.";
			$texto_mail = "<b><font color=green>Confirmacion del JOB que ejecuta Alineamiento Planficado automaticamente. La tarea se realizo correctamente.</b><br><br>Wget se ejecuto correctamente.</b></font>";			
			Plogged_Mail_Externo_ProrityHight ("",$email_direccion_whs,"","",$texto_asunto,$texto_mail);			
			
		}else{		
			Plogged ($log_file,$modo_ejecucion,1,"ERROR. Wget No se ejecuto correctamente. Salida: $salida_system \n\n");

			$texto_asunto = "ERROR. Alineamiento planificap. La ejecucion de Wget fue fallida.";
			$texto_mail = "<b><font color=red>ERROR en ejecucion de Alineamiento Planificado Salesforce. La tarea programada se ejecuto con errores o no se ejecuto.</b><br><br>No se pudo ejecutar Wget correctamente. Revisar el log para ver si se lanzo algo o nada..</b></font>";
			Plogged_Mail ($email_sistemas,$log_file,$texto_asunto,$texto_mail);
			
			exit 1;			
		};	
		#-------------------------------------------------------------------------------------------------


Plogged ($log_file,$modo_ejecucion,1," ");
Plogged ($log_file,$modo_ejecucion,1," ");
	


Plogged ($log_file,$modo_ejecucion,1,"\n\n");
#-----------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Buscamos errores en LOG para notificar a ROOT
Buscar_Error_En_LOG($modo_ejecucion,$log_file,$email_desarrollo,$email_desarrollo);

#	FICHERO PID. Borramos el fichero PID para liberar la ejecucion.
FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)

#	Purgamos los LOG
Script_Purgado_Logs(4);

#	Pie del Script
Script_Pie;

# Salimos con OK
exit 0;