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
use File::Path qw(make_path);
use Sys::Hostname;

# Librerias globales
use lib 'D:\Intranet\Perl\comun\lib';
# Libreria local Xena
use lib '.\Lib';
use GlobalVariables;
use llogged;
use LIB_ToperCable_Xena;

#**************************************************************************************************************************
#  Extraccion directa de datos Xena para alineamiento planificado
#  Refactorizacion Perl de alineamiento_planificado_run_xena.asp
#  Extrae: CO, Residencial, NIF, Tarifa, BonoCom, Promo, IMSI
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
my $dir_principal			= "D:\\Intranet\\Script\\ToperCable\\Analisis_Planificados\\Xena\\LOGS\\";
my $dir_rot					= strftime("%Y-%m-%d_%H%M%S", localtime(time()));
my $directorio_log			= $dir_principal . $dir_rot;

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


Plogged($log_file, $modo_ejecucion, 1, "- Creando directorio LOGS ($directorio_log)");
eval {
	make_path($directorio_log, { mode => 0755 });
};
if ($@) {
	my $error_message = $@;
	Plogged($log_file, $modo_ejecucion, 3, "ERROR. No se creo directorio ($directorio_log): $error_message");
	$texto_asunto = "ERROR. Extraccion Datos Xena. No se pudo crear directorio LOG.";
	$texto_mail   = "<b><font color=red>Error Extraccion Datos Xena</b><br><br>No se pudo crear el directorio de LOGS ($directorio_log).<br>Error: $error_message</font>";
	Plogged_Mail($email_sistemas, $log_file, $texto_asunto, $texto_mail);
	exit 1;
} else {
	Plogged($log_file, $modo_ejecucion, 2, "OK. Directorio de logs creado correctamente");
}
Plogged($log_file, $modo_ejecucion, 1, " ");


#------------------------------------------------------------------
# Obtenemos los planificados pendientes
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "- Obteniendo Planificados pendientes..");
my @ListPlanificados   = Get_Planificados_Pendientes_Xena();
my $num_planificados   = scalar @ListPlanificados;
Plogged($log_file, $modo_ejecucion, 1, "Total Planificados pendientes: $num_planificados");
Plogged($log_file, $modo_ejecucion, 1, " ");


#------------------------------------------------------------------
# Bucle principal: planificado → MSISDNs → extraccion Xena → UPDATE
#------------------------------------------------------------------
Plogged($log_file, $modo_ejecucion, 1, "Recorriendo listado de PLANIFICADOS..");
if (@ListPlanificados) {

	my $umbral     = 100;	# Frecuencia de log de progreso
	my $batch_size = 100;	# Tamaño del lote de UPDATEs

	foreach my $id_planificado (@ListPlanificados) {

		# Actualizamos contador por si el proceso muere antes del final
		Plogged($log_file, $modo_ejecucion, 1, "Actualizando contador planificado: $id_planificado");
		UPDATE_Xena_Contador($id_planificado);

		# Obtenemos MSISDNs pendientes de este planificado
		Plogged($log_file, $modo_ejecucion, 1, "Obteniendo MSISDN pendientes de planificado: $id_planificado ..");
		my @resultados       = Get_MSISDN_Pendientes_Xena($id_planificado);
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

				# Inicializamos variables de salida
				my $Xena_CO          = "";
				my $Xena_Residencial = "";
				my $Xena_NIF         = "";
				my $Xena_idPerfil    = "";
				my $Xena_BonoCom     = "";
				my $Xena_Promo       = "";
				my $Xena_IMSI        = "";


				#------------------------------------------------------
				# 1. Datos principales del MSISDN desde mvno.pv_msisdn
				#------------------------------------------------------
				Plogged($log_file, $modo_ejecucion, 0, "\t - Obteniendo datos Xena MSISDN: $registro");
				my $xena_data = Get_Xena_MSISDN_Data($registro);

				if (!$xena_data->{result}) {
					Plogged($log_file, $modo_ejecucion, 0, "\t - MSISDN no encontrado en Xena ($registro): $xena_data->{msg}");

				} else {
					$Xena_CO          = $xena_data->{CO};
					$Xena_Residencial = $xena_data->{Residencial};
					$Xena_idPerfil    = $xena_data->{idPerfil};
					$Xena_IMSI        = $xena_data->{imsi};

					Plogged($log_file, $modo_ejecucion, 0, "\t - CO: $Xena_CO | Resi: $Xena_Residencial | idPerfil: $Xena_idPerfil | IMSI: $Xena_IMSI");


					#------------------------------------------------------
					# 2. Datos del cliente (NIF) desde mvno.pv_clientes
					#------------------------------------------------------
					my $cli_data = Get_Xena_Cliente_Data($Xena_Residencial);
					if ($cli_data->{result}) {
						$Xena_NIF = $cli_data->{NIF};
						Plogged($log_file, $modo_ejecucion, 0, "\t - NIF: $Xena_NIF");
					} else {
						Plogged($log_file, $modo_ejecucion, 0, "\t - Cliente no encontrado en Xena: $cli_data->{msg}");
						$Xena_NIF = '';
					}


					#------------------------------------------------------
					# 3. Bono Compartido Xena
					# TODO: implementar cuando se confirme la tabla mvno
					#------------------------------------------------------
					my $bc_data = Get_Xena_BonoCom($Xena_Residencial, $registro);
					$Xena_BonoCom = $bc_data->{result} ? $bc_data->{BonoCom} : '';


					#------------------------------------------------------
					# 4. Promociones Xena
					# TODO: implementar cuando se confirme la tabla mvno
					#------------------------------------------------------
					my $promo_data = Get_Xena_Promos($Xena_Residencial, $registro);
					if ($promo_data->{result}) {
						$Xena_Promo = Ordenar_Xena_Promos($promo_data->{Promos});
					} else {
						$Xena_Promo = '';
					}
				}


				#------------------------------------------------------
				# Acumulamos el UPDATE en el batch
				#------------------------------------------------------
				$sql_actual = "UPDATE topercable.alineamiento_planificado_detalle " .
					"SET co_xena = '$Xena_CO', resi_xena = '$Xena_Residencial', cif_xena = '$Xena_NIF', " .
					"tarifa_xena = '$Xena_idPerfil', bc_xena = '$Xena_BonoCom', promo_xena = '$Xena_Promo', " .
					"imsi_xena = '$Xena_IMSI' " .
					"WHERE planificado_id = $id_planificado AND msisdn = '$registro';";

				Batch_Xena_SQL_Generar(\$sql_actual, \@sql_batch, $batch_size);

				# Log de progreso
				if ($index % $umbral == 0) {
					Plogged($log_file, $modo_ejecucion, 1, "- Procesando MSISDN $registro ($index de $numero_registros)");
				}

				Plogged($log_file, $modo_ejecucion, 0, "*<- Procesado registro $registro\n");

			}	# foreach MSISDN

			# Ejecutamos el resto del batch que no llego al umbral
			Plogged($log_file, $modo_ejecucion, 0, "\t - Ejecutando SQL update resto del batch");
			Batch_Xena_SQL_Ejecutar(\@sql_batch);

		} else {
			Plogged($log_file, $modo_ejecucion, 1, "- No hay MSISDN pendientes para planificado: $id_planificado");
		}

		# Actualizamos el contador final del planificado
		Plogged($log_file, $modo_ejecucion, 1, "Actualizando contador final planificado: $id_planificado");
		UPDATE_Xena_Contador($id_planificado);

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
