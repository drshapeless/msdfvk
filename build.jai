OUTPUT_EXECUTABLE_NAME := "test";

#run {
    set_build_options_dc(.{do_output = false});

    root_options := get_build_options();
    w := compiler_create_workspace("Target workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(root_options, *options);
    options.output_executable_name = OUTPUT_EXECUTABLE_NAME;

    additional_linker_arguments: [..] string;
    array_add(*additional_linker_arguments, "-lm");
    options.additional_linker_arguments = additional_linker_arguments;

    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("test.jai", w);

    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .COMPLETE;
                mc := cast(*Message_Complete) message;
                if mc.error_code != .NONE {
                    exit(1);
                }
                break;
        }
    }

    compiler_end_intercept(w);
}

#import "Compiler";
#import "Basic";
