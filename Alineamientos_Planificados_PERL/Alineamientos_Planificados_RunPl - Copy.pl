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
#FileExists($0,0);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
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

	my $msisdn = "601647053";


Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo datos del cliente..");
	my $result = Get_SF_MSISDN_data($msisdn, $token_sf);
	if ($result->{result}) {
		print "MSISDN: $result->{SF_msisdn}\n";
		print "SF_totalsize: $result->{SF_totalsize}\n";
		print "Estado: $result->{SF_Estado}\n";
		print "Cableoperador: $result->{SF_Cableoperador}\n";
		print "Residencial: $result->{SF_Residencial}\n";
		print "CIF: $result->{SF_CIF}\n";
		print "SF_RootItemId: $result->{SF_RootItemId}\n";		
		print "Marca: $result->{SF_Marca}\n";
		print "Tarifa: $result->{SF_Tarifa}\n";
		print "BonoTarifa: $result->{SF_BonoTarifa}\n";
		print "BonoCompartido: $result->{SF_BonoCompartido}\n";
		print "BonosPromociones: $result->{SF_BonosPromociones}\n";		
	} else {
		print "Error al consultar SF: $result->{SF_Response}\n";
	}
	
Plogged ($log_file,$modo_ejecucion,1," ");

Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo BONOS del MSISDN..");
	my $result2 = Get_SF_MSISDN_Bonos_data($result->{SF_RootItemId}, $token_sf);
	if ( $result2->{result} ) {
		print "SF_RootItemId: $result2->{SF_RootItemId}\n";
		print "SF_totalsize: $result2->{SF_totalsize}\n";
		#print "SF_JSONAttribute: $result2->{SF_JSONAttribute}\n";	
		print "SF_Tarifa: $result2->{SF_Tarifa}\n";
	} else {
		print "Error al consultar SF: $result2->{SF_Response}\n";
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