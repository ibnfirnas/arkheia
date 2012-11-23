open Batteries
open Printf


module RegExp = struct
  let space = Str.regexp " +"
  let space_lead = Str.regexp "^ +"
  let space_trail = Str.regexp " +$"
  let white_space = Str.regexp "[ \t]+"
  let newline = Str.regexp "\n"

  let top_from =
    let from = "^From" in
    let username = ".+" in
    let weekday = "[A-Z][a-z][a-z]" in
    let month = "[A-Z][a-z][a-z]" in
    let day = "[0-9]+" in
    let time = "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" in
    let year = "[0-9][0-9][0-9][0-9]$" in
    Str.regexp
    ( String.concat " +"
      [ from
      ; username
      ; weekday
      ; month
      ; day
      ; time
      ; year
      ]
    )

  let header_tag = Str.regexp "^[a-zA-Z-_]+: "
  let header_data = Str.regexp "^[ \t]+"

  let angle_bracket_open_lead = Str.regexp "^<"
  let angle_bracket_close_trail = Str.regexp ">$"
  let between_angle_bracketed_items = Str.regexp ">[ \t\n]+<"
end


module Str = struct include Str
  let strip s = s
    |> replace_first RegExp.space_lead ""
    |> replace_first RegExp.space_trail ""
end


module GZ = struct include Gzip
  let output_line (oc : out_channel) (line : string) : unit =
    String.iter (fun c -> output_char oc c) line;
    output_char oc '\n'


  let input_line (ic : in_channel) : string =
    let expected_chars = 100 in
    let buffer = Buffer.create expected_chars in
    let rec input_line = function
      | '\n' -> Buffer.contents buffer
      |   c  -> Buffer.add_char buffer c;
                input_line (input_char ic)
    in
    input_line (input_char ic)
end


module Msg = struct
  type t =
    { top_from    : string
    ; from        : string
    ; date        : string
    ; subject     : string
    ; in_reply_to : string
    ; references  : string list
    ; message_id  : string
    ; body        : string list
    }

  type section =
    Headers | Body


  let is_head_tag  l = Str.string_match RegExp.header_tag  l 0
  let is_head_data l = Str.string_match RegExp.header_data l 0


  let clean_id id =
    try Scanf.sscanf id "<%s@>" (fun id -> id)
    with e -> print_endline id; print_endline (dump e); assert false


  let clean_ids data = data
    |> Str.replace_first RegExp.angle_bracket_open_lead ""
    |> Str.replace_first RegExp.angle_bracket_close_trail ""
    |> Str.split RegExp.between_angle_bracketed_items
    |> List.map (Str.global_replace RegExp.white_space "")


  let parse (msg_txt : string) : t =
    let parse_header h =
      if (Str.string_match RegExp.top_from h 0) then
        "TOP_FROM", h
      else
        match Str.full_split RegExp.header_tag h with
        | [Str.Delim tag; Str.Text data] -> Str.strip tag, Str.strip data
        | _ -> print_endline h; assert false
    in

    let pack_msg hs bs =
      let rec pack msg = function
        | [] -> msg

        | ("TOP_FROM"    , data)::hs -> pack {msg with top_from    = data} hs
        | ("From:"       , data)::hs -> pack {msg with from        = data} hs
        | ("Date:"       , data)::hs -> pack {msg with date        = data} hs
        | ("Subject:"    , data)::hs -> pack {msg with subject     = data} hs
        | ("In-Reply-To:", data)::hs -> pack {msg with in_reply_to = data} hs

        | ("References:" , data)::hs ->
          pack {msg with references  = clean_ids data} hs

        | ("Message-ID:" , data)::hs ->
          pack {msg with message_id  = clean_id  data} hs

        | _ -> assert false
      in
      let msg =
        { top_from    = ""
        ; from        = ""
        ; date        = ""
        ; subject     = ""
        ; in_reply_to = ""
        ; references  = []
        ; message_id  = ""
        ; body        = bs
        }
      in
      pack msg hs
    in

    let rec parse h hs' bs' = function
      | Headers, [] | Body, [] -> pack_msg hs' (List.rev bs')

      | Headers, ""::ls ->
        parse "" ((parse_header h)::hs') bs' (Body, ls)

      | Headers, l::ls when is_head_tag l ->
        parse l ((parse_header h)::hs') bs' (Headers, ls)

      | Headers, l::ls when is_head_data l ->
        parse (h ^ l) hs' bs' (Headers, ls)

      | Headers, l::ls -> assert false

      | Body, l::ls -> parse h hs' (l::bs') (Body, ls)
    in

    let h, msg_lines = match (Str.split RegExp.newline msg_txt)with
      | h::msg_lines -> h, msg_lines
      | _ -> print_endline msg_txt; assert false
    in

    parse h [] [] (Headers, msg_lines)


  let bar_major = let bar = String.make 80 '=' in bar.[0] <- '+'; bar
  let bar_minor = let bar = String.make 80 '-' in bar.[0] <- '+'; bar


  let print msg =
    let section bar s = String.concat "\n" [bar; s; bar] in
    let indent_ref = "    " in

    print_endline
    ( String.concat "\n"
      [ section bar_major "| MESSAGE"
      ; section bar_minor "| HEADERS"
      ; sprintf "TOP_FROM:    %s" msg.top_from
      ; sprintf "FROM:        %s" msg.from
      ; sprintf "DATE:        %s" msg.date
      ; sprintf "SUBJECT:     %s" msg.subject
      ; sprintf "IN_REPLY_TO: %s" msg.in_reply_to
      ; sprintf "MESSAGE_ID:  %s" msg.message_id
      ; "REFERENCES:"
      ; String.concat "\n" (List.map (sprintf "%s%s" indent_ref) msg.references)
      ; section bar_minor "| BODY"
      ; String.concat "\n" msg.body
      ]
    );
    print_newline ()
end


module Mbox = struct
  let is_msg_start l =
    Str.string_match RegExp.top_from l 0


  let read_msg s =
    let rec read msg' = match Stream.peek s with
      | None -> String.concat "\n" (List.rev msg')
      | Some line when is_msg_start line -> String.concat "\n" (List.rev msg')
      | Some line -> Stream.junk s; read (line::msg')
    in
    match Stream.peek s with
    | None -> Stream.junk s; None
    | Some line when is_msg_start line -> Stream.junk s; Some (read [line])
    | Some _ -> assert false


  let msg_stream filename =
    let line_stream =
      if Filename.check_suffix filename ".gz" then
        let ic = GZ.open_in filename in
        Stream.from
        (fun _ -> try Some (GZ.input_line ic) with _ -> GZ.close_in ic; None)

      else
        let ic = open_in filename in
        Stream.from
        (fun _ -> try Some (input_line ic) with _ -> close_in ic; None)
    in
    Stream.from (fun _ -> read_msg line_stream)
end


module Options = struct
  type t =
    { mbox_file : string
    }


  let parse () =
    let usage = "" in
    let mbox_file = ref "" in
    let speclist = Arg.align
      [ ("-mbox-file", Arg.Set_string mbox_file, " Path to mbox file.")
      ]
    in
    Arg.parse speclist (fun _ -> ()) usage;

    if !mbox_file = "" then
      failwith "Need path to an mbox file."
    else
      { mbox_file = !mbox_file
      }
end


let main () =
  let o = Options.parse () in
  let mbox = Mbox.msg_stream o.Options.mbox_file in

  Stream.iter  (Msg.parse |- Msg.print)  mbox


let () = main ()
