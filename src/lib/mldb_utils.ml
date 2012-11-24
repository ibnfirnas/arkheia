open Batteries


module RegExp = Mldb_regexp


exception Mkdir_failure of int * string


let mkpath path : unit =
  match Sys.command ("mkdir -p " ^ path) with
  | 0 -> ()
  | n -> raise (Mkdir_failure (n, path))


let histogram lst =
  let hist = Hashtbl.create 1 in
  List.iter
  ( fun e ->
      try let i = Hashtbl.find hist e in Hashtbl.replace hist e (i + 1)
      with Not_found -> Hashtbl.add hist e 1
  )
  lst;
  hist


let strip s = s
  |> Str.replace_first RegExp.spaces_lead ""
  |> Str.replace_first RegExp.spaces_trail ""