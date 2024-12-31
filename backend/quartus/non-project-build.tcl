# Load Quartus Prime Tcl Project package
package require ::quartus::project
load_package flow

set quartus_backend_dir		$::env(QUARTUS_BACKEND_DIR)
set quartus_work_dir 		$::env(QUARTUS_WORKDIR)
set project_name  			$::env(PROJ_NAME)
set revision_name   		$::env(REV_NAME)
set top_module 				$::env(TOP)
set rtl_dirs 				$::env(RTL_DIRS)
set sdc_dirs 				$::env(QUARTUS_SDC_DIRS)
set bram_init_file_dirs		$::env(BRAM_INIT_FILE_DIRS)
set device 					$::env(DEVICE)
set family 					$::env(FAMILY)


proc build_snapshot_dir_and_file_list {snapshot_dir snapshot_file_list filetype dir_list } {
	
	foreach dir $dir_list {
		foreach filename [ glob -- $dir] {
			set filename_without_path [file tail $filename]
			set snapshot_file_name "$snapshot_dir/$filename_without_path"

			# create snapshot of RTL files, so different compile version won't affact each other
			file copy -force $filename $snapshot_file_name

			puts "add file to RTL snapshot: $filename"
			lappend snapshot_file_list [list $filetype $snapshot_file_name]
		}
	}
	return $snapshot_file_list
}

proc addFilesToProj {quartus_work_dir rtl_dir_list sdc_dir_list bram_init_file_dir_list quartus_backend_dir} {

	set verilog_snapshot_dir "$quartus_work_dir/verilog_snapshot_dir"
	set sdc_snapshot_dir "$quartus_work_dir/sdc_snapshot_dir"

	set pcie_ip_file_path "$quartus_backend_dir/ips/pcie/rtile_pcie_hip.ip"
	set iopll_ip_file_path "$quartus_backend_dir/ips/iopll/iopll.ip"
	set reset_release_ip_file_path "$quartus_backend_dir/ips/reset_release/reset_release.ip"
	set eth_ip_file_path "$quartus_backend_dir/ips/eth/ftile_eth_hip.ip"
	set system_clk_and_ftile_ref_clk_ip_file_path "$quartus_backend_dir/ips/system_clk_and_ftile_ref_clk/system_clk_and_ftile_ref_clk.ip"

	file mkdir $verilog_snapshot_dir
	file mkdir $sdc_snapshot_dir

	set snapshot_file_list {}

	set snapshot_file_list [build_snapshot_dir_and_file_list $verilog_snapshot_dir $snapshot_file_list "VERILOG_FILE" $rtl_dir_list]
	set snapshot_file_list [build_snapshot_dir_and_file_list $sdc_snapshot_dir $snapshot_file_list "SDC_FILE" $sdc_dir_list]
	set snapshot_file_list [build_snapshot_dir_and_file_list $verilog_snapshot_dir $snapshot_file_list "TEXT_FILE" $bram_init_file_dir_list]

	# Add ips to the project
	lappend snapshot_file_list [list "IP_FILE" $pcie_ip_file_path]
	lappend snapshot_file_list [list "IP_FILE" $iopll_ip_file_path]
	lappend snapshot_file_list [list "IP_FILE" $reset_release_ip_file_path]
	lappend snapshot_file_list [list "IP_FILE" $eth_ip_file_path]
	lappend snapshot_file_list [list "IP_FILE" $system_clk_and_ftile_ref_clk_ip_file_path]

	

	foreach tuple $snapshot_file_list {
		lassign $tuple filetype filename
		set_global_assignment -name $filetype $filename
		
		puts "add file to project: $filetype $filename"
	}
}



# change into work dir
file mkdir $quartus_work_dir
cd $quartus_work_dir


set need_to_close_project 0
set make_assignments 1

# Check that the right project is open
if {[is_project_open]} {
	if {[string compare $quartus(project) $project_name]} {
		puts "Another project called $quartus(project) is open now, closing it"
		project_close
	}
} 

# Only open if not already open
if {[project_exists $project_name]} {
	project_open -revision $revision_name $project_name
} else {
	project_new -revision $revision_name $project_name
}
set need_to_close_project 1



# Make assignments
if {$make_assignments} {
	addFilesToProj $quartus_work_dir $rtl_dirs $sdc_dirs $bram_init_file_dirs $quartus_backend_dir

	# assign pin location
	source "$quartus_backend_dir/sdc/set_pin_loc.tcl"
	source "$quartus_backend_dir/sdc/fitter_assignments.tcl"

	set_global_assignment -name TOP_LEVEL_ENTITY $top_module
	set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
	set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
	set_global_assignment -name MAX_CORE_JUNCTION_TEMP 100
	set_global_assignment -name DEVICE $device
	set_global_assignment -name FAMILY $family
	set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 256
	set_global_assignment -name PWRMGT_VOLTAGE_OUTPUT_FORMAT "LINEAR FORMAT"
	set_global_assignment -name PWRMGT_LINEAR_FORMAT_N "-12"
	set_global_assignment -name POWER_APPLY_THERMAL_MARGIN ADDITIONAL
	set_global_assignment -name OPTIMIZATION_MODE "SUPERIOR PERFORMANCE WITH MAXIMUM PLACEMENT EFFORT"

	# Including default assignments
	set_global_assignment -name FLOW_ENABLE_DESIGN_ASSISTANT ON -family $family
	set_global_assignment -name TIMING_ANALYZER_MULTICORNER_ANALYSIS ON -family $family
	set_global_assignment -name TDC_CCPP_TRADEOFF_TOLERANCE 0 -family $family
	set_global_assignment -name TIMING_ANALYZER_DO_CCPP_REMOVAL ON -family $family
	set_global_assignment -name PHYSICAL_SHIFT_REGISTER_INFERENCE ON -family $family
	set_global_assignment -name SYNCHRONIZATION_REGISTER_CHAIN_LENGTH 3 -family $family
	set_global_assignment -name SYNTH_RESOURCE_AWARE_INFERENCE_FOR_BLOCK_RAM ON -family $family
	set_global_assignment -name ADVANCED_PHYSICAL_SYNTHESIS_REGISTER_PACKING ON -family $family
	set_global_assignment -name PHYSICAL_SYNTHESIS ON -family $family
	set_global_assignment -name POST_ROUTE_PHYSICAL_SYNTHESIS OFF -family $family
	set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "ACTIVE SERIAL X4" -family $family
	set_global_assignment -name PRESERVE_UNUSED_XCVR_CHANNEL OFF -family $family
	set_global_assignment -name DEVICE_INITIALIZATION_CLOCK INIT_INTOSC -family $family
	set_global_assignment -name OPTIMIZE_HOLD_TIMING "ALL PATHS" -family $family
	set_global_assignment -name OPTIMIZE_MULTI_CORNER_TIMING ON -family $family
	set_global_assignment -name ENABLE_PHYSICAL_DSP_MERGING ON -family $family
	set_global_assignment -name AUTO_DELAY_CHAINS ON -family $family
	set_global_assignment -name ENABLE_ED_CRC_CHECK ON -family $family
	set_global_assignment -name ALLOW_SEU_FAULT_INJECTION OFF -family $family
	set_global_assignment -name FITTER_RESYNTHESIS ON -family $family
	set_global_assignment -name FITTER_EARLY_RETIMING ON -family $family
	set_global_assignment -name FLOW_ENABLE_HYPER_RETIMER_FAST_FORWARD OFF -family $family
	set_global_assignment -name HYPER_RETIMER_FAST_FORWARD_ON_HIERARCHY ON -family $family
	set_global_assignment -name GENERATE_PR_RBF_FILE ON -family $family
	set_global_assignment -name HPS_INITIALIZATION "AFTER INIT_DONE" -family $family
	set_global_assignment -name PROGRAMMING_BITSTREAM_ENCRYPTION_KEY_SELECT "Battery Backup RAM" -family $family
	set_global_assignment -name POWER_USE_DEVICE_CHARACTERISTICS MAXIMUM -family $family
	set_global_assignment -name ACTIVE_SERIAL_CLOCK AS_FREQ_100MHZ -family $family
	set_global_assignment -name EDA_IBIS_MUTUAL_COUPLING ON -section_id eda_board_design_signal_integrity -family $family
	set_global_assignment -name EDA_IBIS_SPECIFICATION_VERSION 5P0 -section_id eda_board_design_signal_integrity -family $family

	# more debug info
	set_global_assignment -name RTL_ANALYSIS_DEBUG_MODE ON

	# Commit assignments
	export_assignments

	execute_flow -compile

	# Close project
	if {$need_to_close_project} {
		project_close
	}
}
