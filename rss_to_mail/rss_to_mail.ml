type mail = Utils.mail = {
  sender		: string;
  subject		: string;
  body		: string
}

module Make (Fetch : sig
       type error
       val fetch : Uri.t -> (string, error) result Lwt.t
     end) =
struct

  module Check_feed = Check_feed.Make (Fetch)
  module Check_scraper = Check_scraper.Make (Fetch)
  module Check_bundle = Check_bundle.Make (Fetch)

  type nonrec mail = mail

  (**
     	 * Check a feed for updates
     	 * Returns the list of generated mails and updated feed datas
     	 * Log informations by calling [log] once for each feed
     	 *)
  let check ~now get_feed_data (feed, options) =
    let updated url = function
      | `Ok (seen_ids, mails) ->
        let seen_ids = SeenSet.filter_removed now seen_ids in
        mails, [ url, `Updated (seen_ids, List.length mails) ]
      | `Uptodate | `Fetch_error _ | `Parsing_error _ as r ->
        [], [ url, r ]
    in
    match feed with
    | Feed_desc.Feed url		->
      let uri, data = Uri.of_string url, get_feed_data url in
      let r = Check_feed.check ~now uri options data in
      Lwt.map (updated url) r
    | Scraper (url, scraper)	->
      let uri, data = Uri.of_string url, get_feed_data url in
      let r = Check_scraper.check ~now uri scraper options data in
      Lwt.map (updated url) r
    | Bundle url				->
      let uri, data = Uri.of_string url, get_feed_data url in
      let r = Check_bundle.check ~now uri options data in
      Lwt.map (updated url) r

end
