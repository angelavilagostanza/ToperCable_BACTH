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


# Añadimos nuestras librerias
use lib 'D:\Intranet\Perl\comun\lib';
use lib '.\lib';
use GlobalVariables;
use llogged;
use LIB_sf_token;


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
};
$email_sistemas 	= $email_desarrollo;

#**************************************************************************************************************************
#  Empezamos

# FICHERO PID. Creamos el fichero PID para evitar solpamiento en ejecuciones
FileExists($0,0);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
#------------------------------------------------------------------
Plogged ($log_file,$modo_ejecucion,1,"\n\n");
Plogged ($log_file,$modo_ejecucion,1," ");



Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo Token de SF..");
	my $token_sf = get_sf_token();
		if ($token_sf =~ /^Error/) {
			Plogged ($log_file,$modo_ejecucion,3,"ERROR No se pudo obtener el Token de Salesforce ($token_sf)");
			#Plogged_Mail($email_root_procesos,$log_file,"ENo se pudo obtener el Token de Salesforce ($token_sf)","No se pudo obtener el Token de Salesforce ($token_sf).<br><br>");
			FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
			exit 1;
		};	
	Plogged ($log_file,$modo_ejecucion,1,"\t Token SF: ($token_sf)");


Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo cambios de tarifas de ayer..");
my $resultados  = Get_SF_Cambio_Tarifa($token_sf);
# Verificar si la llamada fue exitosa
my $numero_de_registros = scalar(@{ $resultados->{SF_Registros} });
Plogged ($log_file,$modo_ejecucion,1,"- Numero de MSISDN: $numero_de_registros ");


Plogged ($log_file,$modo_ejecucion,1,"- Recorriendo resultado..");
if ($resultados->{result}) {
	
		Plogged ($log_file,$modo_ejecucion,1,"- Creando alineamiento..");
		my $planificacion_id = ADD_Alineamiento($numero_de_registros);
		Plogged ($log_file,$modo_ejecucion,1,"- ID nueva planificacion: $planificacion_id ");
		
	
    # Procesar los datos devueltos
    foreach my $registro (@{ $resultados->{SF_Registros} }) {
		#Plogged ($log_file,$modo_ejecucion,1,"\t MSISDN: $registro->{SF_Numero_de_Telefono} ");
        # Procesar otros campos si es necesario

		if ($planificacion_id > 5){
			Plogged ($log_file,$modo_ejecucion,0,"- Añadiendo MSISDN $registro->{SF_Numero_de_Telefono} a la planificiacion $planificacion_id ");			
			ADD_MSISDN_To_Alineamiento($registro->{SF_Numero_de_Telefono},$planificacion_id);
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