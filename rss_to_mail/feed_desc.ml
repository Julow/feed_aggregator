type t =
	| Feed of string
	| Scraper of string * Scraper.t
