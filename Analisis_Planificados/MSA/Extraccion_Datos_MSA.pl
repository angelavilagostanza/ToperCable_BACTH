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
# Libreria local MSA
use lib '.\Lib';
use GlobalVariables;
use llogged;
use LIB_ToperCable_MSA;

#**************************************************************************************************************************
#  Extraccion de IMSI desde MSA (API REST HLR) para alineamiento planificado
#  Llama al endpoint: GET /voice-mobile/northbound-common/msisdns/{msisdn}/hlr
#  Extrae: imsi_msa
#  Se ejecuta despues del paso Inventario y antes de Match_Sistemas
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
my @ListPlanificados   = Get_Planificados_Pendientes_MSA();
my $num_planificados   = scalar @ListPlanificados;
Plogged($log_file, $modo_ejecucion, 1, "Total Planificados pendientes: $num_planificados");
Plogged($log_file, $modo_ejecucion, 1, " ");


#------------------------------------------------------------------
# Bucle principal: planificado → MSISDNs → llamada MSA API → UPDATE imsi_msa
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "Recorriendo listado de PLANIFICADOS..");
if (@ListPlanificados) {

	my $umbral     = 100;	# Frecuencia de log de progreso
	my $batch_size = 100;	# Tamaño del lote de UPDATEs

	foreach my $id_planificado (@ListPlanificados) {

		# Actualizamos contador por si el proceso muere antes del final
		Plogged($log_file, $modo_ejecucion, 1, "Actualizando contador planificado: $id_planificado");
		UPDATE_MSA_Contador($id_planificado);

		# Obtenemos MSISDNs pendientes de este planificado
		Plogged($log_file, $modo_ejecucion, 1, "Obteniendo MSISDN pendientes de planificado: $id_planificado ..");
		my @resultados       = Get_MSISDN_Pendientes_MSA($id_planificado);
		my $numero_registros = scalar @resultados;
		Plogged($log_file, $modo_ejecucion, 1, "Total MSISDN recibidos: $numero_registros");
		Plogged($log_file, $modo_ejecucion, 1, " ");

		if (@resultados) {

			# Variables para el UPDATE en lotes
			my @sql_batch;
			my $sql_actual = "";

			my $index = 0;
			foreach my $registro (@resultados) {
				$index++;

				# Validar que tiene exactamente 9 digitos numericos
				next unless defined $registro && $registro =~ /^\d{9}$/;

				my $MSA_IMSI   = "";
				my $MSA_Estado = "";

				#------------------------------------------------------
				# Llamada al endpoint MSA HLR
				#------------------------------------------------------
				Plogged($log_file, $modo_ejecucion, 0, "\t - Consultando MSA MSISDN: $registro");
				my $msa_data = Get_MSA_MSISDN_Data($registro);

				if (!$msa_data->{result}) {
					my $prefijo = ($msa_data->{msg} eq '[MSA.NoExiste]') ? 'NO_EXISTE' : 'ERROR';
					Plogged($log_file, $modo_ejecucion, 1, "- $prefijo Get_MSA_MSISDN_Data ($registro): $msa_data->{msg}");
					$MSA_IMSI = $msa_data->{msg};

				} else {
					$MSA_IMSI   = $msa_data->{imsi};
					$MSA_Estado = $msa_data->{estado};

					if ($MSA_IMSI eq '') {
						$MSA_IMSI = "[Error.MSA.IMSI_Vacio]";
					}

					Plogged($log_file, $modo_ejecucion, 0, "\t - IMSI: $MSA_IMSI | Estado: $MSA_Estado | Brand: $msa_data->{brand}");
				}


				#------------------------------------------------------
				# Acumulamos el UPDATE en el batch
				#------------------------------------------------------
				$sql_actual = "UPDATE topercable.alineamiento_planificado_detalle " .
					"SET msa = '$MSA_Estado', imsi_msa = '$MSA_IMSI' " .
					"WHERE planificado_id = $id_planificado AND msisdn = '$registro';";

				Batch_MSA_SQL_Generar(\$sql_actual, \@sql_batch, $batch_size);

				# Log de progreso
				if ($index % $umbral == 0) {
					Plogged($log_file, $modo_ejecucion, 1, "- Procesando MSISDN $registro ($index de $numero_registros)");
				}

				Plogged($log_file, $modo_ejecucion, 0, "*<- Procesado registro $registro\n");

			}	# foreach MSISDN

			# Ejecutamos el resto del batch que no llego al umbral
			Plogged($log_file, $modo_ejecucion, 1, "\t - Ejecutando SQL update resto del batch");
			Batch_MSA_SQL_Ejecutar(\@sql_batch);

		} else {
			Plogged($log_file, $modo_ejecucion, 1, "- No hay MSISDN pendientes para planificado: $id_planificado");
		}

		# Actualizamos el contador final del planificado
		Plogged($log_file, $modo_ejecucion, 1, "Actualizando contador final planificado: $id_planificado");
		UPDATE_MSA_Contador($id_planificado);

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
