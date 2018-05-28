(** Various operators used here *)

let (<) node ?ns name = Xml.child ?ns name node
let (<<) node ?ns name = Xml.children ?ns name node
let (>) nopt f = Option.map f nopt
let (>$) nopt f = Option.flat_map f nopt
let (>>) nlst f = List.map f nlst
let (>>$) nlst f = List.filter_map f nlst
