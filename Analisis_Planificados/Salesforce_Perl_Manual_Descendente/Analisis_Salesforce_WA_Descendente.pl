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
use JSON;
use Encode;

# Añadimos nuestras librerias
use lib 'D:\Intranet\Perl\comun\lib';
use lib '.\lib';
use GlobalVariables;
use llogged;
use LIB_ToperCable_SF;
use LIB_Toper_APPS;			# Libreria comun a Toper, como el Token de Salesforce

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
	#FileExists($0,0);	# 0:Comprobacion (Inicio)		1:Borrado (Final)
	#------------------------------------------------------------------	
};
$email_sistemas 	= $email_desarrollo;
#**************************************************************************************************************************
#  Empezamos
Plogged ($log_file,$modo_ejecucion,1,"\n");


Plogged ($log_file,$modo_ejecucion,1,"- Obteniendo Planificados pendientres..");
my @ListPlanificados  = Get_Planificados_Pendientes();
# Verificar si la llamada fue exitosa
my $numero_de_planificados = scalar @ListPlanificados;
Plogged ($log_file,$modo_ejecucion,1,"Total Planificados pendientes: $numero_de_planificados ");
Plogged ($log_file,$modo_ejecucion,1," ");


Plogged ($log_file,$modo_ejecucion,1,"Recorriendo listado de PLANIFICADOS..");
if (@ListPlanificados) {

	my $umbral	  = 100;	# Umbral apra pinter la evolucion del bucle
	#my $token_sf 	= get_sf_token();	
	my $token_sf = Get_Token_SF();
	#Plogged ($log_file,$modo_ejecucion,0,"- Token SF: $token_sf ..");
	
	# variables para el UDATED en lotes
	my @sql_batch;
	my $sql_actual = "";
	my $batch_size = 100;	
	
	foreach my $id_planificado (@ListPlanificados) {
			
			#$id_planificado = 969;  # 1064 test   969 cartera

			# Actualizamso contador por si muere antes del final
			Plogged ($log_file,$modo_ejecucion,1,"Actualizando Contador de Planificado: $id_planificado ");
			UPDATE_Alineamiento_Contador ($id_planificado);


			Plogged ($log_file,$modo_ejecucion,1,"Obteniendo MSISDN pendientes de planificado: $id_planificado ..");
			my @resultados  = Get_MSISDN_Planificados($id_planificado);
			# Verificar si la llamada fue exitosa
			my $numero_de_registros = scalar @resultados;
			Plogged ($log_file,$modo_ejecucion,1,"Total MSISDN recibidos: $numero_de_registros ");
			Plogged ($log_file,$modo_ejecucion,1," ");
			

			Plogged ($log_file,$modo_ejecucion,1,"Recorriendo listado de MSISDN..");
			if (@resultados) {
				
				# Procesar los datos devueltos
				my $index = 0;
				foreach my $registro (@resultados) {
					$index++;					
					
					# Validar que tiene exactamente 9 dígitos numéricos
					next unless defined $registro && $registro =~ /^\d{9}$/;		
					
					# Inicializamos las Variables		
					my $SF_Estado                   = "";
					my $SF_Cableoperador            = "";
					my $SF_Residencial              = "";
					my $SF_CIF                      = "";
					my $RootItemId        			= "";
					my $SF_Tarifa                   = "";
					my $SF_BonoTarifa               = "";
					my $SF_BonoCompartido           = "";
					my $SF_BonoCompartido_Name      = "";
					my $SF_BonosPromociones         = "";
					my $SF_Cableoperador_JSON       = "";
					my $SF_Cablero_Bono_CO          = "";
					my $SF_ID_Tarificador           = "";		
					
					my $record  = Get_SF_Activo($token_sf,$registro);
						if (!$record->{result}) {
							$SF_Cableoperador 	= "Error.SF";
							$SF_Residencial		= "Error.SF";
							$SF_CIF				= "Error.SF";
							$RootItemId			= "Error.SF";
							$SF_Tarifa			= "Error.SF";
							Plogged ($log_file,$modo_ejecucion,1,"- ERROR $record->{SF_Response} ");
						}else{
							my $totalsize = $record->{SF_Response}->{totalSize};
							Plogged ($log_file,$modo_ejecucion,0,"\t - totalsize2: $totalsize ");
							if ($totalsize eq "0"){
								Plogged ($log_file,$modo_ejecucion,1,"- Alerta No hay Asset activos para MSISDN $registro (totalSize: $totalsize) ");
							}elsif ($totalsize ne "0"){
								my $datos = $record->{SF_Response}->{records}[0];
								$SF_Estado 			= $datos->{Status};
								$SF_Cableoperador 	= $datos->{vlocity_cmt__BillingAccountId__r}->{Cableoperador};
								$SF_Residencial		= $datos->{Account}->{Residencial};
								$SF_CIF				= $datos->{Account}->{Numero_de_documento__c};
								$RootItemId			= $datos->{vlocity_cmt__RootItemId__c};
								$SF_Tarifa			= $datos->{Product2}->{Name};					
								
									
									if($RootItemId ne ""){
										#Plogged ($log_file,$modo_ejecucion,0,"\t - Get Asset Tarifa ");
										my $record_tarifa  = Get_SF_AssetTarifa($token_sf,$RootItemId);
										if (!$record_tarifa->{result}) {
											$SF_ID_Tarificador = "[Error.Jerarquia.Asset_Tarifa]";
										}else{
											if ($record_tarifa->{SF_Response}->{totalSize} eq "0") {
												$SF_ID_Tarificador = "[Error.Jerarquia.Asset_Tarifa -> No existe]";
											}elsif ($record_tarifa->{SF_Response}->{totalSize} eq "1") {
												
												my $datos_tarifa = $record_tarifa->{SF_Response}->{records}[0]{'vlocity_cmt__JSONAttribute__c'};
												# Decodificar el JSON anidado
												my $atributos_tarifa;
												eval {
													$atributos_tarifa = decode_json(encode("UTF-8", $datos_tarifa));
													1;
												} or do {
													$SF_BonoCompartido     = "[Error.Jerarquia.Asset_Tarifa.JSON]";
													$SF_Cableoperador_JSON = "[Error.Jerarquia.Asset_Tarifa.JSON]";
													next;  # o return según contexto
												};


													#$atributos_tarifa = decode_json(encode("UTF-8",$datos_tarifa));	
													if (ref($atributos_tarifa) ne 'HASH' || !exists $atributos_tarifa->{"Xena_Code_Category"}) {
														$SF_BonoCompartido 		= "[Error.Jerarquia.Asset_Tarifa]";
														$SF_Cableoperador_JSON	= "[Error.Jerarquia.Asset_Tarifa]";
													}else{	
													
														#Recorreemos los registgros hasta obetener el CO JSON
														foreach my $atributo (@{ $atributos_tarifa->{"Datos_Tecnicos_Movil"} }) {
															if ($atributo->{attributeuniquecode__c} eq "IDCLIENTE") {
																$SF_Cableoperador_JSON = $atributo->{attributeRunTimeInfo}->{value};
																last;
															}
														}										
														
														#Recorreemos los registgros hasta obetener el ID_TARIFICADOR 
														foreach my $atributo2 (@{ $atributos_tarifa->{"Bonos_Tarifa"} }) {
															if ($atributo2->{attributeuniquecode__c} eq "ID_Tarificador") {
																$SF_ID_Tarificador = $atributo2->{attributeRunTimeInfo}->{value};
																last;
															}
														}
													}
												
											}elsif ($record_tarifa->{SF_Response}->{totalSize} > 1){
												$SF_ID_Tarificador = "[Error.Jerarquia.Asset_Tarifa -> Duplicado]";
											}
										}									
										
										
										#Plogged ($log_file,$modo_ejecucion,0,"\t - Get Asset BonoCompartido ");							
										my $record_bonocompartido1  = Get_SF_AssetBonoCompartido($token_sf,$RootItemId);
										if (!$record_bonocompartido1->{result}) {
											# Algo salio mal
											$SF_BonoCompartido = "[Error.Jerarquia.Asset_BonoCompartido]";
										}else{								
											if ($record_bonocompartido1->{SF_Response}->{totalSize} eq "1") {									
												my $datos_bonocompartido1 = $record_bonocompartido1->{SF_Response}->{records}[0]{'MM_BonoDatos_AssetId__c'};
												if ($datos_bonocompartido1 ne "0"){
													
													my $record_bonocompartido2  = Get_SF_AssetBonoCompartido_BonoDatos($token_sf,$datos_bonocompartido1);
													if (!$record_bonocompartido2->{result}) {														
														$SF_BonoCompartido = "[Error.Activo_BonoCompartido -> No existe]";
													}else{
														
														if ($record_bonocompartido2->{SF_Response}->{totalSize} ne "0") {
															$SF_Cablero_Bono_CO = $record_bonocompartido2->{SF_Response}->{records}[0]{vlocity_cmt__BillingAccountId__r}->{CO_Codigo_Xena__c};
															
															# Guardamos y validamos el JSON Atrubute
															my $atributos_bonocompartido;
															my $json_str = $record_bonocompartido2->{SF_Response}->{records}[0]{'vlocity_cmt__JSONAttribute__c'};
															if (defined $json_str && $json_str ne '') {
																$atributos_bonocompartido = decode_json($json_str);													
																#$atributos_bonocompartido = decode_json($record_bonocompartido2->{SF_Response}->{records}[0]{'vlocity_cmt__JSONAttribute__c'});
																# Verificamos que tenemos un JSON valido
																if (ref($atributos_bonocompartido) ne 'HASH' || !exists $atributos_bonocompartido->{"Xena_Code_Category"}) {
																	$SF_BonoCompartido = "[Error.Jerarquia.BonoCompartido]";
																}else{												
																	#Recorreemos los registgros hasta obetener el Bono Compartido
																	foreach my $atributo3 (@{ $atributos_bonocompartido->{"Xena_Code_Category"} }) {
																		if ($atributo3->{attributeuniquecode__c} eq "ExternalIDXenaRC") {
																			$SF_BonoCompartido = $atributo3->{value__c};
																			last;
																		}
																	}
																}													
															} else {																
																$SF_BonoCompartido = "[Error.JSON.Activo_BonoCompartido]";
															}
															
															# Si recibimos mas de 1 asset es que el Activo Bono Compartido tiene mal la jerarquia
															if ($record_bonocompartido2->{SF_Response}->{totalSize} > 1) {
																$SF_BonoCompartido = $SF_BonoCompartido . " [Error.Jerarquia.Activo_BonoCompartido]";
															}
														}
													}										
												}
											}elsif($record_bonocompartido1->{SF_Response}->{totalSize} > 0){
												$SF_BonoCompartido = "[Error.Jerarquia.BonoCompartido > Asset_BonoCompartido_duplicado]";
											}											
										}
										
										
										
										#Plogged ($log_file,$modo_ejecucion,0,"\t - Get Asset Promociones ");							
										my $record_promociones  = Get_SF_AssetPromociones($token_sf,$RootItemId);
										if (!$record_promociones->{result}) {
											$SF_BonosPromociones = "[Error.Jerarquia.Promociones]"
										}else{
											if ($record_promociones->{SF_Response}->{totalSize} ne "0") {
												
												for (my $Z = 0; $Z <= $record_promociones->{SF_Response}->{totalSize} - 1; $Z++) {

													my $atributos_promociones = decode_json($record_promociones->{SF_Response}->{records}[$Z]{'vlocity_cmt__JSONAttribute__c'});																							# Verificamos que tenemos un JSON valido
													if (ref($atributos_promociones) ne 'HASH' || !exists $atributos_promociones->{"Xena_Code_Category"}) {
														$SF_BonosPromociones = "[Error.Jerarquia.Promociones]";
													}else{
													
														#Recorreemos los registgros hasta obetener La promocion
														foreach my $atributo4 (@{ $atributos_promociones->{"Xena_Code_Category"} }) {
															if ($atributo4->{attributeuniquecode__c} eq "ExternalIDXenaRC") {
																Plogged ($log_file,$modo_ejecucion,0,"\t - PROMO: $atributo4->{value__c} ");
																#$SF_BonosPromociones = $atributo4->{value__c};
																
																if ($SF_BonosPromociones ne ""){
																	$SF_BonosPromociones = $SF_BonosPromociones . "," . $atributo4->{value__c};
																}else{
																	$SF_BonosPromociones = $atributo4->{value__c};
																}																
																last;
															}
														}
													}
												}
											}
										}
										$SF_BonosPromociones = Ordenar_Valores_Alfanumericos($SF_BonosPromociones);										
									}

								if ($totalsize > 1) {
									$SF_Residencial = $SF_Residencial . " [Error.Jerarquia.ActivoDuplicado]";
								}
							}
						}
						
					
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_Estado: $SF_Estado ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_Cableoperador: $SF_Cableoperador ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_Cableoperador_JSON: $SF_Cableoperador_JSON ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_Cablero_Bono_CO: $SF_Cablero_Bono_CO ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_Residencial: $SF_Residencial ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_CIF: $SF_CIF ");
					# Plogged ($log_file,$modo_ejecucion,1,"- RootItemId: $RootItemId ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_Tarifa: $SF_Tarifa ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_ID_Tarificador: $SF_ID_Tarificador ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_BonoCompartido: $SF_BonoCompartido ");
					# Plogged ($log_file,$modo_ejecucion,1,"- SF_BonosPromociones: $SF_BonosPromociones ");
					
					
					#  Verifiamos que el Cablero es el mismo en los 3 casos
					if ($SF_Cablero_Bono_CO eq ""){
						$SF_Cablero_Bono_CO = $SF_Cableoperador
					}
					my $Codigo_Cablero;
					if ($SF_Cableoperador eq $SF_Cableoperador_JSON && $SF_Cableoperador eq $SF_Cablero_Bono_CO) {
						# Las 3 son iguales
						$Codigo_Cablero = $SF_Cableoperador;
					} else {
						# Al menos dos son diferentes
						# Concatenar las dos que sean diferentes
						# Primero detectamos cuáles son diferentes
						
						my @valores = ($SF_Cableoperador, $SF_Cableoperador_JSON, $SF_Cablero_Bono_CO);
						my %seen;
						my @diferentes;

						foreach my $v (@valores) {
							next unless defined($v) && $v ne '';         # Saltar si es undef o cadena vacía. Ocurre cuando el JSON esta vacio porque no existe el Asset. Aprecera como ERROR_TAR
							push @diferentes, $v unless $seen{$v}++;
						}

						# Si hay más de un valor diferente (lo normal si no son iguales)
						# Concatenamos los diferentes separados por coma (o como prefieras)
						$Codigo_Cablero = join('-', @diferentes);
					}
					#Plogged ($log_file,$modo_ejecucion,1,"- Codigo_Cablero $Codigo_Cablero ");
					#------------------------------------------
					
					
					#Verificamos el esidencial
					if ($SF_Estado eq "In Progress"){
						$SF_Residencial = $SF_Residencial . "-TMP";
					}
					#Plogged ($log_file,$modo_ejecucion,1,"- SF_Residencial $SF_Residencial ");
					#------------------------------------------		
					
					
					
					#-------------------------------------------------------------------------------------------
					# v1 Plogged ($log_file,$modo_ejecucion,0,"\t - Actualizando registro $registro ");
					#UPDATE_Alineamiento_Detalle ($registro,$id_planificado,$Codigo_Cablero,$SF_Residencial,$SF_CIF,$SF_ID_Tarificador,$SF_BonoCompartido,$SF_BonosPromociones);
					
					# v2 Creamos el update actual
					$sql_actual = "UPDATE topercable.alineamiento_planificado_detalle SET co_sf = '$Codigo_Cablero', resi_sf = '$SF_Residencial', cif_sf = '$SF_CIF', tarifa_sf = '$SF_ID_Tarificador', bc_sf = '$SF_BonoCompartido', promo_sf = '$SF_BonosPromociones' WHERE planificado_id = $id_planificado and msisdn = '$registro';";					

					# Acumulamos el update en una array para ejcutarlos en paquetes al llegar al Umbral
					Batch_SQL_Generar(\$sql_actual, \@sql_batch, $batch_size);
					
					# Pintamos el progreso
					if ($index % $umbral == 0) {		
						Plogged ($log_file,$modo_ejecucion,1,"- Procesando MSISDN $registro ($index de $numero_de_registros)");
					}
					#-------------------------------------------------------------------------------------------
					

					Plogged ($log_file,$modo_ejecucion,0,"*<- Procesado registro $registro \n");
				}
			} else {
				Plogged ($log_file,$modo_ejecucion,1,"- No hya MSISDN pendientes ID Planificado: $id_planificado ");
			}

			# Ejecutamos el UPDATE acumulado que no se ejecuto por no llegar al Umbral
			Plogged ($log_file,$modo_ejecucion,0,"\t\t - Ejecutando SQL update Resto");
			Batch_SQL_Ejecutar(\@sql_batch);

			Plogged ($log_file,$modo_ejecucion,1,"Actualizando Contador de Planificado: $id_planificado ");
			UPDATE_Alineamiento_Contador ($id_planificado);
	}
}


Plogged ($log_file,$modo_ejecucion,1,"\n\n");
#-----------------------------------------------------------------------------------------------------------------------------------------------------------------
#	Buscamos errores en LOG para notificar a ROOT
Buscar_Error_En_LOG($modo_ejecucion,$log_file,$email_desarrollo,$email_desarrollo);

#	FICHERO PID. Borramos el fichero PID para liberar la ejecucion.
#FileExists($0,1);	# 0:Comprobacion (Inicio)		1:Borrado (Final)

#	Purgamos los LOG
Script_Purgado_Logs(10);

#	Pie del Script
Script_Pie;

# Salimos con OK
exit 0;