type mail = Mail_body.t = {
  sender : string;
  subject : string;
  body_html : string;
  body_text : string;
}

type feed_data = int64 * SeenSet.t
(** [last_update * seen_ids] *)

module Make (Fetch : sig
  type error

  val fetch : Uri.t -> (string, error) result Lwt.t
end) (Feed_datas : sig
  type t

  val get : t -> string -> feed_data option

  val set : t -> string -> feed_data -> t
end) =
struct
  type update = { entries : int }

  type error =
    [ `Parsing_error of (int * int) * string
    | `Fetch_error of Fetch.error
    ]

  type log = string * [ `Updated of update | error | `Uptodate ]

  module Process_feed = struct
    (* Remove date for IDs that disapeared from the feed: 1 month *)
    let remove_date_from = Int64.add 2678400L

    (** Empty list of filter match everything *)
    let match_any_filter = function
      | [] -> fun _ -> true
      | filters -> (
          function
          | Feed.{ title = Some title; _ } ->
              let match_ (regexp, expctd) =
                try
                  ignore (Str.search_forward regexp title 0);
                  expctd
                with Not_found -> not expctd
              in
              List.exists match_ filters
          | { title = None; _ } -> true
        )

    let process ~now _feed_uri options seen_ids feed =
      let match_any_filter = match_any_filter options.Feed_desc.filter in
      let new_ids, entries =
        Array.fold_right
          (fun entry (ids, news) ->
            match Feed.entry_id entry with
            | Some id when match_any_filter entry ->
                let news =
                  if SeenSet.is_seen id seen_ids then news else entry :: news
                in
                (id :: ids, news)
            | Some _ | None -> (ids, news)
            (* Ignore entries without an ID *))
          feed.Feed.entries ([], [])
      in
      let seen_ids = SeenSet.new_ids (remove_date_from now) new_ids seen_ids in
      (feed, seen_ids, entries)
  end

  module Check_feed = struct
    let prepare_mail ~sender feed options entry =
      let label = options.Feed_desc.label in
      Mail_body.gen_mail ~sender ?label feed [ entry ]

    let fetch uri =
      let resolve_uri = Uri.resolve "" uri in
      let parse_content contents =
        match Feed_parser.parse ~resolve_uri (`String (0, contents)) with
        | exception Feed_parser.Error (pos, err) ->
            Error (`Parsing_error (pos, err))
        | feed -> Ok feed
      in
      Fetch.fetch uri
      |> Lwt.map (function
           | Error e -> Error (`Fetch_error e)
           | Ok contents -> parse_content contents)

    let prepare ~sender feed options entries =
      List.map (prepare_mail ~sender feed options) entries
  end

  module Check_scraper = struct
    let fetch uri scraper =
      Fetch.fetch uri
      |> Lwt.map (function
           | Error e -> Error (`Fetch_error e)
           | Ok contents ->
               let resolve_uri = Uri.resolve "" uri in
               Ok (Scraper.scrap ~resolve_uri scraper contents))

    let prepare ~sender feed options entries =
      List.map (Check_feed.prepare_mail ~sender feed options) entries
  end

  module Check_bundle = struct
    let fetch = Check_feed.fetch

    let prepare ~sender feed options = function
      | [] -> []
      | entries ->
          let label = options.Feed_desc.label in
          [ Mail_body.gen_mail ~sender ?label feed entries ]
  end

  type nonrec mail = mail

  type nonrec feed_data = feed_data

  let sender_name feed_uri feed options =
    let ( ||| ) opt def =
      match opt with Some "" | None -> def () | Some v -> v
    in
    options.Feed_desc.title ||| fun () ->
    feed.Feed.feed_title ||| fun () ->
    Uri.host feed_uri ||| fun () -> Uri.to_string feed_uri

  let update_feed ~now uri options seen_ids ~fetch ~prepare =
    let process = function
      | Error e -> e
      | Ok feed ->
          let feed, seen_ids, entries =
            Process_feed.process ~now uri options seen_ids feed
          in
          let sender = sender_name uri feed options in
          let mails = prepare ~sender feed options entries in
          `Ok (seen_ids, mails)
    in
    Lwt.map process (fetch uri)

  (** [Some (first_update, seen_ids)] if the feed need to be updated. *)
  let should_update ~now data options =
    match data with
    | Some (last_update, seen_ids) ->
        if Utils.is_uptodate now last_update options
        then None
        else Some (false, seen_ids)
    | None -> Some (true, SeenSet.empty)

  (** Call [update] to update the feed. *)
  let check_feed ~now url feed_datas options ~fetch ~prepare =
    let update_result ~first_update = function
      | (`Fetch_error _ | `Parsing_error _) as error -> (url, error)
      | `Ok (seen_ids, mails) ->
          let seen_ids = SeenSet.filter_removed now seen_ids in
          (* Don't send anything on first update *)
          let mails = if first_update then [] else mails in
          (url, `Updated (mails, seen_ids))
    in
    let uri = Uri.of_string url and data = Feed_datas.get feed_datas url in
    match should_update ~now data options with
    | None -> Lwt.return (url, `Uptodate)
    | Some (first_update, seen_ids) ->
        Lwt.map
          (update_result ~first_update)
          (update_feed ~now uri options seen_ids ~fetch ~prepare)

  (** * Check a feed for updates * Returns the list of generated mails and
      updated feed datas * Log informations by calling [log] once for each feed *)
  let check_feed_desc ~now feed_datas (feed, options) =
    match feed with
    | Feed_desc.Feed url ->
        let fetch = Check_feed.fetch and prepare = Check_feed.prepare in
        check_feed ~now url feed_datas options ~fetch ~prepare
    | Scraper (url, scraper) ->
        let fetch uri = Check_scraper.fetch uri scraper
        and prepare = Check_scraper.prepare in
        check_feed ~now url feed_datas options ~fetch ~prepare
    | Bundle url ->
        let fetch = Check_bundle.fetch and prepare = Check_bundle.prepare in
        check_feed ~now url feed_datas options ~fetch ~prepare

  let reduce_updated ~now (acc_datas, acc_mails, logs) = function
    | url, `Updated (mails, seen_ids) ->
        let data = (now, seen_ids) in
        let logs = (url, `Updated { entries = List.length mails }) :: logs in
        (Feed_datas.set acc_datas url data, mails @ acc_mails, logs)
    | (_, (`Fetch_error _ | `Parsing_error _ | `Uptodate)) as log ->
        (acc_datas, acc_mails, log :: logs)

  (** Update a list of feeds in parallel *)
  let check_all ~now feed_datas feeds =
    Lwt_list.map_p (check_feed_desc ~now feed_datas) feeds
    |> Lwt.map (fun results ->
           let feed_datas, mails, logs =
             List.fold_left (reduce_updated ~now) (feed_datas, [], []) results
           in
           (feed_datas, mails, List.rev logs))
end
