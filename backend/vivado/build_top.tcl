set vivado_backend_dir		$::env(VIVADO_BACKEND_DIR)
set vivado_work_dir 		$::env(VIVADO_WORKDIR)
set project_name  			$::env(PROJ_NAME)
set top_module 				$::env(TOP)

set rtl_dirs 				$::env(RTL_DIRS)
set sdc_dirs 				$::env(VIVADO_SDC_DIRS)
set bram_init_file_dirs		$::env(BRAM_INIT_FILE_DIRS)

set part $::env(VIVADO_PART)

set current_time [clock format [clock seconds] -format "%Y-%m-%d-%H-%M-%S"]

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


proc createProject {vivado_work_dir rtl_dir_list sdc_dir_list bram_init_file_dir_list vivado_backend_dir} {
    global dir_output part device dir_rtl dir_sdc dir_ip_gen dir_bsv_gen
    global ooc_module_names


    set verilog_snapshot_dir "$vivado_work_dir/verilog_snapshot_dir"
	set sdc_snapshot_dir "$vivado_work_dir/sdc_snapshot_dir"

	file mkdir $verilog_snapshot_dir
	file mkdir $sdc_snapshot_dir

	set snapshot_file_list {}

	# add our own files (especially sdc files) last, so all the signals provided by other IP will be available.
	set snapshot_file_list [build_snapshot_dir_and_file_list $verilog_snapshot_dir $snapshot_file_list "VERILOG_FILE" $rtl_dir_list]
	set snapshot_file_list [build_snapshot_dir_and_file_list $sdc_snapshot_dir $snapshot_file_list "SDC_FILE" $sdc_dir_list]
	set snapshot_file_list [build_snapshot_dir_and_file_list $verilog_snapshot_dir $snapshot_file_list "TEXT_FILE" $bram_init_file_dir_list]

    read_verilog [ glob $verilog_snapshot_dir/*.v ]
    add_files -norecurse [glob $verilog_snapshot_dir/*.bin]

    read_xdc [ glob $sdc_snapshot_dir/*.sdc ]

	set_param general.maxthreads 24
	set device [get_parts $part]; # xcvu13p-fhgb2104-2-i; #
	set_part $device
}


proc runSynthDesign {args} {
	global vivado_work_dir top_module
	synth_design -top $top_module -flatten_hierarchy none
	write_checkpoint -force $vivado_work_dir/post_synth_design.dcp
    write_xdc -force -exclude_physical $vivado_work_dir/post_synth.xdc
}

proc runPlacement {args} {
    global vivado_work_dir top_module current_time

    if {[dict get $args -open_checkpoint] == true} {
        open_checkpoint $vivado_work_dir/post_synth_design.dcp
    }

    opt_design -remap -verbose

    if {[dict exist $args -directive]} {
        set directive [dict get $args -directive]
        place_design -verbose  -directive ${directive}
    } else {
        set directive ""
        place_design -verbose 
    }

    file mkdir $vivado_work_dir/${current_time}_${directive}
    write_checkpoint -force $vivado_work_dir/${current_time}_${directive}/post_place.dcp
    write_xdc -force -exclude_physical $vivado_work_dir/${current_time}_${directive}/post_place.
}

proc runRoute {args} {
    global vivado_work_dir

    if {[dict get $args -open_checkpoint] == true} {
        open_checkpoint $vivado_work_dir/post_place.dcp
    }

    route_design

    proc runPPO { {num_iters 1} {enable_phys_opt 1} } {
        for {set idx 0} {$idx < $num_iters} {incr idx} {
            place_design -post_place_opt; # Better to run after route
            if {$enable_phys_opt != 0} {
                phys_opt_design
            }
            route_design
            if {[get_property SLACK [get_timing_paths ]] >= 0} {
                break; # Stop if timing closure
            }
        }
    }

    # runPPO 4 1; # num_iters=4, enable_phys_opt=1

    write_checkpoint -force $vivado_work_dir/post_route.dcp
    write_xdc -force -exclude_physical $vivado_work_dir/post_route.xdc

    write_verilog -force $vivado_work_dir/post_impl_netlist.v -mode timesim -sdf_anno true

}

createProject $vivado_work_dir $rtl_dirs $sdc_dirs $bram_init_file_dirs $vivado_backend_dir

runSynthDesign

runPlacement -open_checkpoint -false -directive ExtraNetDelay_high
runRoute -open_checkpoint -false