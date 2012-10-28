using Gtk;

namespace GmailFeed {

	/**
	 * The GmailIcon represents the status icon that actually sits in the notification area along
	 * with the popup that displays messages when they are received.
	 **/
	public class GmailIcon : GLib.Object {
		/**
		 * The icon that sits in the notification area
		 **/
		private StatusIcon icon;
		/**
		 * The right click menu
		 **/
		private Gtk.Menu popup_menu;
		/**
		 * The mailbox where we store the mail we get
		 **/
		private Mailbox mailbox;
		/**
		 * The feed we are connected to so we can get mail
		 **/
		private FeedController feed;

		/**
		 * The window and box we will display when the user wants to view their mail.
		 * The window is needed for showing and hiding, while the message_box is needed
		 * so we can access its contents and update them as needed.
		 **/
		private Window message_window;
		private Box message_box;
		/**
		 * Position of the top left corner of the window
		 **/
		private int window_x;
		private int window_y;
		/**
		 * If an update is requested, the message window will be redrawn.
		 * Normally the window is only drawn when an update_complete signal is received.
		 **/
		private bool request_update;

		/**
		 * The dialog box for logging in. Also the delegate for passing our credentials to the feed
		 **/
		private Dialog login_dialog;
		private AuthDelegate ad;
		/**
		 * Update is called automatically every X seconds once logged in. We need to cancel this action
		 * if we lose our connection for some reason. So we need to keep track of its id.
		 **/
		private uint timer_id;
		private bool timer_set;

		/**
		 * The pictures to show in the icon
		 **/
		private static string MAIL_ICON = "/usr/share/gmailnotify/mail.png";
		private static string NO_MAIL_ICON = "/usr/share/gmailnotify/nomail.png";
		private static string ERROR_ICON = "/usr/share/gmailnotify/error.png";

		public GmailIcon() {
			icon = new StatusIcon();
			mailbox = new Mailbox();
			feed = new FeedController();
			popup_menu = new Gtk.Menu();
			message_window = new Window(WindowType.POPUP);
			timer_set = false;

			build_icon();
			build_login_dialog();
			build_message_window();

			connect_feed_mailbox_signals();
			connect_feed_icon_signals();

			icon.set_visible(true);
		}

		/**
		 * Constructs the login dialog. This is just a dialog where the user enters their name and password.
		 * Since we keep the box around, we have their information saved and can show it later so if reauthentication is
		 * needed they just need to click login and not fill out their info again.
		 **/
		private void build_login_dialog() {
			login_dialog = new Dialog.with_buttons("Login", null, DialogFlags.MODAL);
			try {
				login_dialog.set_icon_from_file(MAIL_ICON);
			} catch(Error e) {
			}

			var table = new Table(2, 2, false);

			var name_label = new Label("Username:");
			name_label.set_alignment(0, 0.5f);
			var name_entry = new Entry();
			name_entry.width_chars = 12;

			table.attach_defaults(name_label, 0, 1, 0, 1);
			table.attach_defaults(name_entry, 1, 2, 0, 1);

			var pass_label = new Label("Password:");
			pass_label.set_alignment(0, 0.5f);
			var pass_entry = new Entry();
			pass_entry.width_chars = 12;
			pass_entry.visibility = false;
			pass_entry.invisible_char = '*';
			pass_entry.activates_default = true;

			table.attach_defaults(pass_label, 0, 1, 1, 2);
			table.attach_defaults(pass_entry, 1, 2, 1, 2);

			var box = login_dialog.get_content_area();
			box.pack_start(table, true, true);

			login_dialog.set_default(login_dialog.add_button("Login", 1));
			login_dialog.add_button("Cancel", 0);

			login_dialog.show_all();

			ad = () => {
				return {name_entry.text, pass_entry.text};
			};
		}

		/**
		 * Calls the login dialog, if the login button is pressed, try to log in.
		 **/
		public void login() {
			var response = login_dialog.run();

			if(response == 1) {
				feed.login(ad);
				icon.set_tooltip_text("Logging In...");
			}

			login_dialog.hide();
		}

		/**
		 * Builds the status icon. This involves building the icon and the popup menu.
		 * We also connect the appropriate signals to make it functional.
		 **/
		private void build_icon() {
			icon.set_from_file(NO_MAIL_ICON);
			icon.set_tooltip_text("Disconnected...");

			var login = new Gtk.MenuItem.with_label("Login");
			var update = new Gtk.MenuItem.with_label("Update");
			var quit = new Gtk.MenuItem.with_label("Quit");

			login.activate.connect(() => {
				this.login();
			});

			update.activate.connect(() => {
				feed.update();
				icon.set_tooltip_text("Updating...");
			});

			/**
			 * We send the feed a shutdown signal. It sends us a signal back when it is shutdown.
			 * Then we receive that signal and stop ourselves.
			 **/
			quit.activate.connect(() => {
				feed.shutdown();
			});

			/**
			 * This is the shutdown signal that we receive from the feed
			 **/
			feed.feed_closed.connect(() => {
				Gtk.main_quit();
			});

			popup_menu.append(login);
			popup_menu.append(update);
			popup_menu.append(quit);

			popup_menu.show_all();
			update.hide();

			feed.login_success.connect(() => {
				login.hide();
				update.show();
			});

			feed.connection_error.connect(() => {
				login.show();
				update.hide();
			});

			icon.popup_menu.connect((b,t) => {
				popup_menu.popup(null, null, icon.position_menu, b, t);
			});

			/**
			 * When the icon is clicked, we want to show the messages if there are any, otherwise we don't want to
			 * show an empty window. We resize the window to too small before we show it so that it sizes itself
			 * properly and doesn't have extra white space
			 **/
			icon.activate.connect(() => {
				if(mailbox.size > 0) {
					if(message_window.visible) {
						message_window.hide();
					} else {

						Gdk.Rectangle rect;
						Gdk.Screen screen;
						Orientation orientation;
						icon.get_geometry(out screen, out rect, out orientation);

						int x;
						x = icon.screen.get_width();

						window_y = 30;
						window_x = x - 405;

						message_window.move(window_x, window_y);
						message_window.resize(5, 5);
						message_window.show_all();
					}
				}
			});

		}

		/**
		 * Sets up some basic things for the window that will show the messages.
		 **/
		private void build_message_window() {
			Gdk.RGBA white = Gdk.RGBA();
			white.parse("#fff");

			var ebox = new EventBox();
			message_box = new Box(Orientation.VERTICAL, 5);
			ebox.override_background_color(StateFlags.NORMAL, white);

			/**
			 * We want the window to hide if we mouse out of it, but we don't want it to happen immediately in case
			 * the user accidentally goes out of the window.
			 * So we use a timeout which starts when the user leaves the window, but is cancelled if they re-enter it.
			 **/
			uint event_id = 0;
			bool id_set = false;

			ebox.enter_notify_event.connect((e) => {
				if(id_set) {
					Source.remove(event_id);
					id_set = false;
				}
				return false;
			});

			ebox.leave_notify_event.connect((e) => {
				if(!(e.detail == Gdk.NotifyType.INFERIOR)) {
					event_id = Timeout.add_seconds(1, () => {
						message_window.hide();
						return false;
					});
					id_set = true;
				}
				return false;
			});

			ebox.add(message_box);
			message_window.add(ebox);

		}

		/**
		 * Set up connections between the mailbox and the feed
		 **/
		private void connect_feed_mailbox_signals() {
			// When we get a new message we need to connect its signals to the feed so they will do something useful
			feed.new_message.connect((m) => {
				var mail = new MailItem(m);
				var id = mail.id;
				mailbox.add_message(mail);

				mail.mark_read_clicked.connect(() => {
					feed.mark_read(id);
				});

				mail.archive_clicked.connect(() => {
					feed.archive(id);
				});

				mail.spam_clicked.connect(() => {
					feed.spam(id);
				});

				mail.delete_clicked.connect(() => {
					feed.trash(id);
				});

				mail.star_clicked.connect(() => {
					feed.toggle_starred(id);
				});

				mail.important_clicked.connect(() => {
					feed.toggle_important(id);
				});
			});

			/**
			 * When we get a new message we also need to update the message_box.
			 * Since the previous signal connection added the message to the mailbox, and the mailbox is sorted,
			 * we look through the mailbox and find where this item should be.
			 * Then reposition the visual in the message_box so it is displayed in the correct position
			 **/
			feed.new_message.connect((m) => {
				var visual = mailbox[m.id].visual;
				int c = 0;
				foreach(var mess in mailbox.items) {
					if(mess.id == m.id) {
						message_box.pack_start(visual, false, false, 5);
						message_box.reorder_child(visual, c);
						break;
					}
					c++;
				}
			});

			/**
			 * A hacky way to display a notification when new mail is received
			 **/
			feed.new_message.connect((m) => {
				try {
					Process.spawn_command_line_sync("notify-send --hint=int:transient:1 -i %s \"%s\" \"%s\"".printf(MAIL_ICON, m.author, m.subject));
				} catch(Error e) {
				}
			});

			/**
			 * The following signals are always followed by a message_removed signal. In that signal we will check
			 * if an update of the window is needed. During a normal update several messages might be removed, so we
			 * don't want to redraw the window until they are all done, but for an individual message we would like to
			 * redraw the window as soon as we have confirmation that it was removed.
			 **/
			feed.message_read.connect(() => {
				request_update = true;
			});

			feed.message_archived.connect(() => {
				request_update = true;
			});

			feed.message_spammed.connect(() => {
				request_update = true;
			});

			feed.message_trashed.connect(() => {
				request_update = true;
			});

			/**
			 * We need to remove the message from our message window, since it was removed from the feed
			 * This needs to happen before we remove the message from our mailbox since that is our link to the visual
			 **/
			feed.message_removed.connect((id) => {
				var visual = mailbox[id].visual;
				message_box.remove(visual);
				if(mailbox.size == 1) {
					message_window.hide();
					message_window.resize(5, 2);
				}
			});

			/**
			 * The message is removed from the feed, so remove it from the mailbox.
			 **/
			feed.message_removed.connect((id) => {
				mailbox.remove_message(id);
			});

			/**
			 * Here we update everything if we have been requested to
			 **/
			feed.message_removed.connect(() => {
				if(request_update) {
					var count = mailbox.size;
					if(count == 0) {
						icon.set_tooltip_text("No mail...");
						icon.set_from_file(NO_MAIL_ICON);
					} else if(count == 1) {
						icon.set_tooltip_text("There is 1 new message...");
						icon.set_from_file(MAIL_ICON);
					} else {
						icon.set_tooltip_text("There are %d new messages...".printf(count));
						icon.set_from_file(MAIL_ICON);
					}
					if(message_window.visible) {
						message_window.hide();
						message_window.resize(5, 5);
						if(count > 0) {
							message_window.show_all();
						}
					} else {
						message_window.resize(5, 5);
					}
				}
				request_update = false;
			});

			/**
			 * Signals to toggle the starred / important status of a message
			 **/
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

			/**
			 * If a connection error occurs we need to reactivate any messages that had pending requests since we
			 * don't know if the action went through or not. Otherwise we could have messages stuck in the mailbox that
			 * we have no way of removing without a restart
			 **/
			feed.connection_error.connect(() => {
				mailbox.reactivate_all();
			});
		}

		/**
		 * Connect signals from the feed that we want to alter the icon or tooltip in some way.
		 **/
		private void connect_feed_icon_signals() {
			feed.login_success.connect(() => {
				icon.set_from_file(NO_MAIL_ICON);
				icon.set_tooltip_text("Updating...");
				feed.update();
				if(timer_set) {
					Source.remove(timer_id);
				}
				timer_id = Timeout.add_seconds(120, () => {
					feed.update();
					return true;
				});
				timer_set = true;
			});

			/**
			 * If there is a connection error, show the login box and remove the update timer.
			 * If the user cancels the login request, they can select login from the right click menu later.
			 **/
			feed.connection_error.connect(() => {
				icon.set_from_file(ERROR_ICON);
				icon.set_tooltip_text("Connection Error...");
				if(timer_set) {
					Source.remove(timer_id);
					timer_set = false;
				}
				login();
			});

			feed.update_complete.connect(() => {
				var count = mailbox.size;
				if(count == 0) {
					icon.set_tooltip_text("No mail...");
					icon.set_from_file(NO_MAIL_ICON);
				} else if(count == 1) {
					icon.set_tooltip_text("There is 1 new message...");
					icon.set_from_file(MAIL_ICON);
				} else {
					icon.set_tooltip_text("There are %d new messages...".printf(count));
					icon.set_from_file(MAIL_ICON);
				}
				if(message_window.visible) {
					message_window.hide();
					message_window.resize(5, 5);
					if(count > 0) {
						message_window.show_all();
					}
				} else {
					message_window.resize(5, 5);
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
