all:
	valac-0.16 --enable-experimental -D GLIB_2_32 --pkg libsoup-2.4 --pkg gee-1.0 --pkg gtk+-3.0 --thread ./gmailicon.vala ./mailbox.vala ./feedcontroller.vala ./feed.vala --main=GmailFeed.main -o gmailnotify

Hello this is a test. I wonder if it will work
