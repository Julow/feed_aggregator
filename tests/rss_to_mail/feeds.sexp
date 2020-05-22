((smtp
  (server dummy)
  (from from_addr)
  (auth login password)
 )
 (to some_address)
 (default_refresh 2)
 (feeds (
	(atom.atom (filter "title"))
	./atom.atom
	(rss.rss (refresh (at 18:00)))
	((bundle ././rss.rss) (label "Label") (title "Title") (filter "2"))
	(./././rss.rss (filter (not "Title") "2"))
	((bundle empty.rss))
	no_title.rss
	content_type.atom
  (with-options ((label "Lbl"))
   ./empty.rss
   ././empty.rss)
  https://some-website/relative.atom
  https://some-website/relative.rss

  error.rss
)))
