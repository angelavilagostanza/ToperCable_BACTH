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
# Libreria local Inventario
use lib '.\Lib';
use GlobalVariables;
use llogged;
use LIB_ToperCable_Inventario;

#**************************************************************************************************************************
#  Extraccion de datos de Inventario BPM para alineamiento planificado
#  Refactorizacion Perl de alineamiento_planificado_run_inventario.asp
#  Consulta endpoints CO y SME para obtener co_inv y resi_inv por MSISDN
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
# Obtenemos los planificados pendientes
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "- Obteniendo Planificados pendientes..");
my @ListPlanificados   = Get_Planificados_Pendientes_Inventario();
my $num_planificados   = scalar @ListPlanificados;
Plogged($log_file, $modo_ejecucion, 1, "Total Planificados pendientes: $num_planificados");
Plogged($log_file, $modo_ejecucion, 1, " ");


#------------------------------------------------------------------
# Bucle principal: planificado → MSISDNs → consulta Inventario → UPDATE
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "Recorriendo listado de PLANIFICADOS..");
if (@ListPlanificados) {

	my $umbral     = 100;	# Frecuencia de log de progreso
	my $batch_size = 100;	# Tamaño del lote de UPDATEs

	foreach my $id_planificado (@ListPlanificados) {

		# Actualizamos contador por si el proceso muere antes del final
		Plogged($log_file, $modo_ejecucion, 1, "Actualizando contador planificado: $id_planificado");
		UPDATE_INV_Contador($id_planificado);

		# Obtenemos registros pendientes de este planificado
		Plogged($log_file, $modo_ejecucion, 1, "Obteniendo registros pendientes de planificado: $id_planificado ..");
		my @resultados       = Get_MSISDN_Pendientes_Inventario($id_planificado);
		my $numero_registros = scalar @resultados;
		Plogged($log_file, $modo_ejecucion, 1, "Total registros recibidos: $numero_registros");
		Plogged($log_file, $modo_ejecucion, 1, " ");

		if (@resultados) {

			# Variables para el UPDATE en lotes
			my @sql_batch;
			my $sql_actual = "";

			my $index = 0;
			foreach my $registro (@resultados) {
				$index++;

				my $det_id = $registro->{id};
				my $msisdn = $registro->{msisdn};

				# Validar que tiene exactamente 9 digitos numericos
				next unless defined $msisdn && $msisdn =~ /^\d{9}$/;

				my $INV_Cablero     = '';
				my $INV_Residencial = '';

				#------------------------------------------------------
				# Consulta Inventario BPM (CO primero, SME como fallback)
				#------------------------------------------------------
				Plogged($log_file, $modo_ejecucion, 0, "\t - Consultando Inventario MSISDN: $msisdn");
				my $inv_data = Get_INV_MSISDN_Data($msisdn);

				if ($inv_data->{result}) {
					$INV_Cablero     = $inv_data->{Cablero};
					$INV_Residencial = $inv_data->{Residencial};
					Plogged($log_file, $modo_ejecucion, 0, "\t - Endpoint: $inv_data->{endpoint} | Cablero: $INV_Cablero | Residencial: $INV_Residencial");
				} else {
					Plogged($log_file, $modo_ejecucion, 0, "\t - MSISDN no encontrado en Inventario ($msisdn): $inv_data->{msg}");
				}

				#------------------------------------------------------
				# Acumulamos el UPDATE en el batch (usa id de detalle)
				#------------------------------------------------------
				$sql_actual = "UPDATE topercable.alineamiento_planificado_detalle " .
					"SET co_inv = '$INV_Cablero', resi_inv = '$INV_Residencial' " .
					"WHERE id = $det_id;";

				Batch_INV_SQL_Generar(\$sql_actual, \@sql_batch, $batch_size);

				# Log de progreso
				if ($index % $umbral == 0) {
					Plogged($log_file, $modo_ejecucion, 1, "- Procesando MSISDN $msisdn ($index de $numero_registros)");
				}

			}	# foreach registro

			# Ejecutamos el resto del batch que no llego al umbral
			Plogged($log_file, $modo_ejecucion, 1, "\t - Ejecutando SQL update resto del batch");
			Batch_INV_SQL_Ejecutar(\@sql_batch);

		} else {
			Plogged($log_file, $modo_ejecucion, 1, "- No hay registros pendientes para planificado: $id_planificado");
		}

		# Actualizamos el contador final del planificado
		Plogged($log_file, $modo_ejecucion, 1, "Actualizando contador final planificado: $id_planificado");
		UPDATE_INV_Contador($id_planificado);

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
