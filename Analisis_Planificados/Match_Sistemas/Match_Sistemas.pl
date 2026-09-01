#!C:Perl\bin\perl.exe -w
use DBI;
use Switch;
use POSIX "strftime";
use utf8;
use warnings;
use strict;
use Time::Local;
use File::Copy;
use DateTime::Locale;
use Sys::Hostname;

# Librerias globales
use lib 'D:\Intranet\Perl\comun\lib';
# Libreria local Match
use lib '.\Lib';
use GlobalVariables;
use llogged;
use LIB_ToperCable_Match;

#**************************************************************************************************************************
#  Match entre sistemas para alineamiento planificado
#  Refactorizacion Perl de alineamiento_planificado_run_MatchFinal.asp
#  Compara datos SF vs Xena vs Inventario vs MSA y calcula RESULTADO por MSISDN
#  Estados de resultado: OK | ERROR_INV | ERROR_TAR | ERROR_BCO | ERROR_PRO |
#                        ERROR_CODSF | ERROR_CIF | ERROR_COD | ERROR_AST | ERROR_MSA
#**************************************************************************************************************************

Script_Cabecera;

#-------------------------------------------------------------------------------------
our $email_sistemas;
our $email_direccion_whs;
our $email_desarrollo;

my $texto_asunto;
my $texto_mail;
#-------------------------------------------------------------------------------------

$modo_ejecucion				= 1;	# 0=produccion  1=Debugger

if ($modo_ejecucion == 0) {
	$email_sistemas		= $email_desarrollo;
	$email_direccion_whs= $email_desarrollo;
}

#**************************************************************************************************************************
# Empezamos

# FICHERO PID para evitar solapamiento
Plogged($log_file, $modo_ejecucion, 1, "- Bloqueando proceso. Creando fichero PID");
FileExists($0, 0);	# 0:Comprobacion (Inicio)   1:Borrado (Final)
#------------------------------------------------------------------


#------------------------------------------------------------------
# Obtenemos los planificados pendientes de Match (estado 0, 1 o 2)
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "- Obteniendo Planificados para Match..");
my @ListPlanificados = Get_Planificados_Match();
my $num_planificados = scalar @ListPlanificados;
Plogged($log_file, $modo_ejecucion, 1, "Total Planificados: $num_planificados");
Plogged($log_file, $modo_ejecucion, 1, " ");


#------------------------------------------------------------------
# Bucle principal: planificado → comprobacion pendientes → match → estado
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "Recorriendo listado de PLANIFICADOS..");
if (@ListPlanificados) {

	foreach my $planificado (@ListPlanificados) {

		my $planificado_id     = $planificado->{id};
		my $planificado_nombre = $planificado->{nombre};
		my $planificado_estado = $planificado->{estado};

		Plogged($log_file, $modo_ejecucion, 1, "Planificado: $planificado_id | $planificado_nombre | Estado: $planificado_estado");

		#------------------------------------------------------
		# Comprobamos si hay datos pendientes de procesar
		#------------------------------------------------------
		my $pendiente = Get_Pendiente_Planificacion($planificado_id);
		Plogged($log_file, $modo_ejecucion, 1, "PendientePlanificacion ($planificado_id): $pendiente");

		my $match_pendiente = 0;

		if ($pendiente == 0) {
			Plogged($log_file, $modo_ejecucion, 1, "\t -> Match: SI. Ejecutando..");

			#------------------------------------------------------
			# Ejecutamos el MATCH
			#------------------------------------------------------
			my $match_result = Put_Match_Alineamiento($planificado_id);

			if ($match_result == 1) {

				# Verificamos si quedan MSISDN sin resultado
				$match_pendiente = Get_Match_Pendiente($planificado_id);
				Plogged($log_file, $modo_ejecucion, 1, "\t -> MatchPendiente ($planificado_id): $match_pendiente");

				if ($match_pendiente == 0) {
					# Terminado: todos los MSISDN tienen resultado
					Plogged($log_file, $modo_ejecucion, 2, "\t -> Planificado $planificado_id TERMINADO. Actualizando estado = 3");
					UPDATE_Match_Estado($planificado_id, 3);
				} else {
					# Sigue en match
					Plogged($log_file, $modo_ejecucion, 1, "\t -> Planificado $planificado_id sigue en Match ($match_pendiente pendientes). Actualizando estado = 2");
					UPDATE_Match_Estado($planificado_id, 2);
				}
			}

		} else {
			# Hay datos aun sin procesar, devolvemos a estado 1
			Plogged($log_file, $modo_ejecucion, 1, "\t -> Match: NO, sigue pendiente. Actualizando estado = 1");
			UPDATE_Match_Estado($planificado_id, 1);
		}

		#------------------------------------------------------
		# Contamos los errores y los guardamos (siempre, independientemente del estado)
		#------------------------------------------------------
		my $num_desalineamientos = Get_NumDesalineamientos_Planificado($planificado_id);
		Plogged($log_file, $modo_ejecucion, 1, "\t -> Desalineamientos ($planificado_id): $num_desalineamientos");
		UPDATE_Match_Desalineamiento($planificado_id, $num_desalineamientos);

		Plogged($log_file, $modo_ejecucion, 1, " ");

	}	# foreach planificado

}


Plogged($log_file, $modo_ejecucion, 1, "\n\n");
#------------------------------------------------------------------
# Buscamos errores en LOG para notificar
Buscar_Error_En_LOG($modo_ejecucion, $log_file, $email_desarrollo, $email_desarrollo);

# FICHERO PID. Liberamos ejecucion
FileExists($0, 1);	# 0:Comprobacion (Inicio)   1:Borrado (Final)

# Purgamos logs
Script_Purgado_Logs(3);
Script_Purgado_Logs_Directorios(3);

# Pie del script
Script_Pie;

exit 0;
