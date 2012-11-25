open Batteries
open Printf


type options =
  { mbox_file    : string
  ; list_name    : string
  ; dir_messages : string
  ; dir_index    : string
  ; operation    : string
  ; query        : string
  }


let parse_options () =
  let executable = Sys.argv.(0) in
  let usage = executable ^ " -operation [ build_index ]\n" in

  let mbox_file = ref "" in
  let data_dir  = ref "data" in
  let list_name = ref "" in
  let operation = ref "" in
  let query     = ref "" in

  let speclist = Arg.align
    [ ("-mbox-file", Arg.Set_string mbox_file, " Path to mbox file.")
    ; ("-list-name", Arg.Set_string list_name, " Name of the mailing list.")
    ; ("-operation", Arg.Set_string operation, " Operation to perform.")
    ; ("-query",     Arg.Set_string query,     " Search query (if operation is 'search').")
    ]
  in

  Arg.parse speclist (fun _ -> ()) usage;

  if !operation = "" then
    failwith "Please specify an operation to perform."

  else if !operation = "search" && !query = "" then
    failwith "Please specify -query 'search terms' ."

  else if !mbox_file = "" then
    failwith "Need path to an mbox file."

  else if !list_name = "" then
    failwith "Need name of the mailing list."

  else
    let data_dir =
      String.concat "/" [!data_dir; "lists"; !list_name]
    in
    { mbox_file    = !mbox_file
    ; list_name    = !list_name
    ; dir_messages = String.concat "/" [data_dir; "messages"]
    ; dir_index    = String.concat "/" [data_dir; "index"]
    ; operation    = !operation
    ; query        = String.lowercase !query
    }


let main () =
  let opt = parse_options () in

  match opt.operation with
  | "build_index" ->
    let msg_stream = Mldb.Mbox.msg_stream opt.mbox_file in
    Mldb.Index.build opt.dir_index opt.dir_messages msg_stream

  | "search" ->
    let start_time = Sys.time () in
    let index = Mldb.Index.load opt.dir_index in
    let time_to_load = (Sys.time ()) -. start_time in

    let start_time = Sys.time () in
    let query = List.hd (Str.split Mldb.RegExp.white_spaces opt.query) in
    let results = Mldb.Index.lookup index query in
    let time_to_query = (Sys.time ()) -. start_time in

    List.iter print_endline results;

    print_newline ();
    print_newline ();
    Printf.printf "LOAD   TIME: %f\n" time_to_load;
    Printf.printf "LOOKUP TIME: %f\n" time_to_query

  | other -> failwith ("Invalid operation: " ^ other)


let () = main ()
