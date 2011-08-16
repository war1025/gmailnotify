using Gtk;

namespace GmailFeed {

	public class GmailIcon : GLib.Object {
		private StatusIcon icon;
		private Menu popup_menu;
		private Mailbox mailbox;
		private FeedController feed;

		private Dialog login_dialog;
		private AuthDelegate ad;

		public GmailIcon() {
			icon = new StatusIcon();
			mailbox = new Mailbox();
			feed = new FeedController();
			popup_menu = new Menu();

			build_icon();
			build_login_dialog();

			connect_feed_mailbox_signals();
			connect_feed_icon_signals();

			icon.set_visible(true);
		}

		private void build_login_dialog() {
			login_dialog = new Dialog.with_buttons("Login", null, DialogFlags.MODAL);

			var table = new Table(2, 2, false);

			var name_label = new Label("Username:");
			var name_entry = new Entry();
			name_entry.width_chars = 12;

			table.attach_defaults(name_label, 0, 1, 0, 1);
			table.attach_defaults(name_entry, 1, 2, 0, 1);

			var pass_label = new Label("Password:");
			var pass_entry = new Entry();
			pass_entry.width_chars = 12;
			pass_entry.visibility = false;
			pass_entry.invisible_char = '*';

			table.attach_defaults(pass_label, 0, 1, 1, 2);
			table.attach_defaults(pass_entry, 1, 2, 1, 2);

			unowned Box box = (Box) login_dialog.get_content_area();
			box.pack_start(table, true, true);

			login_dialog.add_button("Login", 1);
			login_dialog.add_button("Cancel", 0);

			login_dialog.show_all();

			ad = () => {
				return {name_entry.text, pass_entry.text};
			};
		}

		public void login() {
			var response = login_dialog.run();

			if(response == 1) {
				feed.login(ad);
			}

			login_dialog.hide();
		}

		private void build_icon() {
			icon.set_from_file("./nomail.png");
			icon.set_tooltip_text("No mail...");

			var login = new MenuItem.with_label("Login");
			var update = new MenuItem.with_label("Update");
			var quit = new MenuItem.with_label("Quit");

			login.activate.connect(() => {
				this.login();
			});

			update.activate.connect(() => {
				feed.update();
			});

			quit.activate.connect(() => {
				feed.shutdown();
			});

			feed.feed_closed.connect(() => {
				Gtk.main_quit();
			});

			popup_menu.append(login);
			popup_menu.append(update);
			popup_menu.append(quit);

			popup_menu.show_all();

			feed.login_success.connect(() => {
				login.hide();
			});

			feed.connection_error.connect(() => {
				login.show();
			});

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
			feed.login_success.connect(() => {
				feed.update();
			});

			feed.connection_error.connect(() => {
				login();
			});

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
		icon.login();

		Gtk.main();
	}
}
