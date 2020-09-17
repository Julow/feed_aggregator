type weekday =
  [ `Mon
  | `Tue
  | `Wed
  | `Thu
  | `Fri
  | `Sat
  | `Sun
  ]

type refresh_options =
  [ `Every of float  (** Every [n] hours *)
  | `At of int * int  (** Every days at [hour, min] *)
  | `At_weekly of weekday * int * int  (** Every weeks on [day, hour, minute]*)
  ]

type filter_target =
  [ `Title
  | `Content  (** Matches both the summary and the full content. *)
  ]

type filter = {
  target : filter_target;
  regexp : Str.regexp;
  expected : bool;
}

type options = {
  refresh : refresh_options;  (** Update interval *)
  title : string option;  (** Override the feed's title *)
  label : string option;  (** Appended to the content *)
  no_content : bool;  (** If the content should be removed *)
  filter : filter list;  (** Filter entries by regex *)
  to_ : string option;  (** Destination email address *)
}

let make_options ?(refresh = `Every 6.) ?title ?label ?(no_content = false)
    ?(filter = []) ?to_ () =
  { refresh; title; label; no_content; filter; to_ }

type _ desc =
  | Feed : string -> [< `In_bundle | `Any ] desc
  | Scraper : string * Scraper.t -> [< `In_bundle | `Any ] desc
  | Bundle : [> `In_bundle ] desc -> [< `Any ] desc

type t = [ `Any ] desc * options

let url_of_feed = function
  | Feed url | Scraper (url, _) | Bundle (Feed url) | Bundle (Scraper (url, _))
    ->
      url
