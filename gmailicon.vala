using Gtk;

namespace GmailFeed {

	public class GmailIcon : GLib.Object {
		private StatusIcon icon;
		private Menu popup_menu;
		private Mailbox mailbox;
		private FeedController feed;

		public GmailIcon() {
			icon = new StatusIcon();
			mailbox = new Mailbox();
			feed = new FeedController();
			popup_menu = new Menu();

			build_icon();

			connect_feed_mailbox_signals();
			connect_feed_icon_signals();

			icon.set_visible(true);
		}

		public void login(AuthDelegate ad) {
			feed.login(ad);
		}

		private void build_icon() {
			icon.set_from_file("./nomail.png");
			icon.set_tooltip_text("No mail...");

			var update = new MenuItem.with_label("Update");
			var quit = new MenuItem.with_label("Quit");

			update.activate.connect(() => {
				feed.update();
			});

			quit.activate.connect(() => {
				feed.shutdown();
				Gtk.main_quit();
			});

			popup_menu.append(update);
			popup_menu.append(quit);

			popup_menu.show_all();

			icon.popup_menu.connect((b,t) => {
				popup_menu.popup(null, null, icon.position_menu, b, t);
			});

		}

		private void connect_feed_mailbox_signals() {
			feed.new_message.connect((m) => {
				mailbox.add_message(m);
			});

			feed.message_removed.connect((id) => {
				mailbox.remove_message(id);
			});

			feed.message_starred.connect((id) => {
				mailbox.star_message(id);
			});

			feed.message_unstarred.connect((id) => {
				mailbox.unstar_message(id);
			});

			feed.message_important.connect((id) => {
				mailbox.important_message(id);
			});

			feed.message_unimportant.connect((id) => {
				mailbox.unimportant_message(id);
			});
		}

		private void connect_feed_icon_signals() {
			feed.new_message.connect((m) => {
				var count = mailbox.size;
				if(count == 1) {
					icon.set_tooltip_text("There is 1 new message...");
					icon.set_from_file("./mail.png");
				} else {
					icon.set_tooltip_text("There are %d new messages...".printf(count));
				}
			});

			feed.message_removed.connect((m) => {
				var count = mailbox.size;
				if(count == 0) {
					icon.set_tooltip_text("No mail...");
					icon.set_from_file("./nomail.png");
				} else if(count == 1) {
					icon.set_tooltip_text("There is 1 new message...");
				} else {
					icon.set_tooltip_text("There are %d new messages...".printf(count));
				}
			});
		}
	}

	void main(string[] args) {
		Gtk.init(ref args);

		var icon = new GmailIcon();
		icon.login(() => {return {args[1], args[2]};});

		Gtk.main();
	}
}
