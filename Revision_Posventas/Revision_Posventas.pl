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
use Try::Tiny;


# Añadimos nuestras librerias
use lib 'D:\Intranet\Perl\comun\lib';
use lib '.\lib';
use GlobalVariables;
use llogged;
use LIB_Toper_Posventas;


#
#  Script que lanza el analisis de alneamiento planificado en Topercable
#  Se ejecuta todos los dias a cada 2 horas
#


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
#	Variables locales
#-------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------
# Descomentar para DEBUG
# Esta variable machaca la de GlobalVariables 0:DEBUG  1:PRODUCCION				Tipo mensaje: 0:DEBUG	1:INFO	2:OK	3:ERROR
$modo_ejecucion = 1;
if ($modo_ejecucion == 0){
	$email_sistemas 	= $email_desarrollo;
	$email_JIRA_PSD 	= $email_desarrollo;
}else{	
	# FICHERO PID. Creamos el fichero PID para evitar solpamiento en ejecuciones
	FileExists($0,0);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
	#------------------------------------------------------------------	
};
$email_sistemas 	= $email_desarrollo;
#**************************************************************************************************************************
#  Empezamos
Plogged ($log_file,$modo_ejecucion,1,"\n\n");
Plogged ($log_file,$modo_ejecucion,1," ");


Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo Cambios de Tarifa de ayer..");
my $resultados  = Get_SF_Posventas();
# Verificar si la llamada fue exitosa
my $numero_de_registros = scalar(@{ $resultados->{SF_Registros} });
Plogged ($log_file,$modo_ejecucion,1," ");
Plogged ($log_file,$modo_ejecucion,1,"- Total MSISDN: $numero_de_registros ");


Plogged ($log_file,$modo_ejecucion,1,"- Recorriendo resultado..");
if ($resultados->{result}) {
	
	Plogged ($log_file,$modo_ejecucion,1,"- Creando analisis..");
	my $planificacion_id = ADD_Alineamiento($numero_de_registros);
	Plogged ($log_file,$modo_ejecucion,1,"- ID nueva planificacion: $planificacion_id ");
		
	
    # Procesar los datos devueltos
    foreach my $registro (@{ $resultados->{SF_Registros} }) {
		#Plogged ($log_file,$modo_ejecucion,1,"\t MSISDN: $registro->{MM_Numero_de_Telefono__c} ");
        # Procesar otros campos si es necesario

		if ($planificacion_id > 5){
			Plogged ($log_file,$modo_ejecucion,0,"- Añadiendo MSISDN $registro->{MM_Numero_de_Telefono__c} a la planificiacion $planificacion_id ");			
			ADD_MSISDN_To_Alineamiento($registro->{MM_Numero_de_Telefono__c},$planificacion_id);
		}		
    }
} else {
	Plogged ($log_file,$modo_ejecucion,3,"- Error al obtener datos de Salesforce: $resultados->{SF_Response} ");
}





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