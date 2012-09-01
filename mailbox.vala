using Gee;
using Gtk;

namespace GmailFeed {

	/**
	 * A MailItem represents an email message and its visual state.
	 * Methods are available to alter the message, and signals are used to
	 * indicate when actions have been requested on the item.
	 **/
	public class MailItem : GLib.Object {
		/**
		 * These signals correspond to the clickable areas of the message when displayed
		 **/
		public signal void mark_read_clicked();
		public signal void archive_clicked();
		public signal void spam_clicked();
		public signal void delete_clicked();
		public signal void star_clicked();
		public signal void important_clicked();

		/**
		 * Used when connecting signals
		 **/
		internal delegate void SignalAction();
		internal delegate bool ShouldAct();

		/**
		 * Visual is the representation of the message that can be displayed in the popup.
		 * It is intended to be embedded in a VBox along with all other messages to represent the unread inbox.
		 * For this reason it should be laid out in a way that is vertically compact.
		 **/
		public Widget visual {get; private set;}

		/**
		 * These fields are scraped from the atom feed
		 **/
		public string author {get; private set; default = "No Author";}
		public string subject {get; private set; default = "No Subject";}
		public string summary {get; private set; default = "";}
		public string id {get; private set; default = "";}
		public DateTime time {get; private set; default = new DateTime.now_local();}

		/**
		 * We have no way of telling if a message is starred or important. These default to false.
		 **/
		public bool starred {get; private set; default = false;}
		public bool important {get; private set; default = false;}

		/**
		 * All of the signals need to be disconnected before this item can be deleted.
		 * Otherwise references hang around and it will not be deleted.
		 * So we collect them and provide a method to remove them all at once.
		 **/
		private Gee.MultiMap<GLib.Object, ulong> signals;

		/**
		 * The way the Feed is set up, only one action can be taken on a message before it is removed.
		 * So we need to deactivate all of the actions once an action is selected. This will be reset if
		 * a connection error signal is received
		 **/
		private bool actions_active;

		/**
		 * The star image represents the state of the message starring. Empty means unstarred. Colored means starred.
		 * A half colored star means a message is queued to toggle the state. State will be toggled when a response signal
		 * is received.
		 * The star is not clickable while a message is queued to toggle state.
		 **/
		private Image star_i;
		private bool star_active;

		/**
		 * The important image represents the state of the message importance. Empty means unimportant. Colored means important.
		 * A half colored icon means a message is queued to toggle the state. State will be toggled when a response signal
		 * is received.
		 * The icon is not clickable while a message is queued to toggle state.
		 **/
		private Image important_i;
		private bool important_active;

		/**
		 * These images are static because they can be reused by all messages.
		 **/
		private static Gdk.Pixbuf STAR_FULL;
		private static Gdk.Pixbuf STAR_EMPTY;
		private static Gdk.Pixbuf STAR_HALF;

		private static Gdk.Pixbuf IMPORTANT_FULL;
		private static Gdk.Pixbuf IMPORTANT_EMPTY;
		private static Gdk.Pixbuf IMPORTANT_HALF;

		static construct {
			// This is the directory the images are located in.
			var base_dir = "/usr/share/gmailnotify";

			try {
				STAR_FULL = new Gdk.Pixbuf.from_file_at_size("%s/star_full.png".printf(base_dir), 16, 16);
				STAR_EMPTY = new Gdk.Pixbuf.from_file_at_size("%s/star_empty.png".printf(base_dir), 16, 16);
				STAR_HALF = new Gdk.Pixbuf.from_file_at_size("%s/star_half.png".printf(base_dir), 16, 16);

				IMPORTANT_FULL = new Gdk.Pixbuf.from_file_at_size("%s/important_full.png".printf(base_dir), 20, 11);
				IMPORTANT_EMPTY = new Gdk.Pixbuf.from_file_at_size("%s/important_empty.png".printf(base_dir), 20, 11);
				IMPORTANT_HALF = new Gdk.Pixbuf.from_file_at_size("%s/important_half.png".printf(base_dir), 20, 11);
			} catch(GLib.Error e) {
				stderr.printf("Could not load images\n");
			}
		}

		/**
		 * GMessage is the Feed representation of a message. It was not used here because it incorporates no visual.
		 * It's methods also require parameters which do not make sense here. This is why inheritance wasn't used.
		 **/
		public MailItem(GMessage mess) {
			this.author = mess.author;
			this.subject = mess.subject;
			this.summary = mess.summary;
			this.id = mess.id;
			this.time = mess.time;
			this.starred = mess.starred;
			this.important = mess.important;

			this.signals = new Gee.HashMultiMap<GLib.Object, ulong>();

			this.actions_active = true;
			this.star_active = true;
			this.important_active = true;

			create_visual();
		}

		/**
		 * Disconnects all of the signals that we added to the visual.
		 * Without calling this, a MailItem will always have active references and not be deleted.
		 **/
		internal void remove_signals() {
			foreach(var obj in signals.get_keys()) {
				foreach(var id in signals.get(obj)) {
					obj.disconnect(id);
				}
			}
			signals.clear();
		}

		internal void connect_signals(EventBox eb, ShouldAct sa, SignalAction enter, SignalAction leave, SignalAction press) {
			var ste = eb.enter_notify_event.connect(() => {
				if(sa()) {
					enter();
				}
				return false;
			});
			var stl = eb.leave_notify_event.connect(() => {
				if(sa()) {
					leave();
				}
				return false;
			});
			var sigid = eb.button_press_event.connect(() => {
				if(sa()) {
					press();
				}
				return false;
			});
			signals.set(eb, ste);
			signals.set(eb, stl);
			signals.set(eb, sigid);
		}

		/**
		 * Build the visual. We use EventBoxes to capture events. The three we care about are enter, leave, and button press.
		 * We use bools to determine if the events should alter state. This allows us to reactivate the pieces if errors happen.
		 **/
		private void create_visual() {
			Gdk.Color white;
			Gdk.Color.parse("#fff", out white);

			var hbox = new Box(Orientation.HORIZONTAL, 5);
			var vbox = new Box(Orientation.VERTICAL, 0);
			hbox.pack_start(vbox, false, false, 5);

			// The subject line
			var subject_box = new Box(Orientation.HORIZONTAL, 0);
			var subject_l = new Label(null);
			subject_l.set_alignment(0, 0.5f);
			subject_l.wrap = true;
			subject_l.set_markup("<span foreground='#000'><b><u>%s</u></b></span>".printf(this.subject));
			var subject_e = new EventBox();
			subject_e.modify_bg(StateType.NORMAL, white);
			subject_e.add(subject_l);
			subject_box.pack_start(subject_e, false, false);
			vbox.pack_start(subject_box, false, false, 1);

			// The from line, with the star and important icon
			var from_box = new Box(Orientation.HORIZONTAL, 0);
			var from_l = new Label(null);
			from_l.set_alignment(0, 0.5f);
			from_l.wrap = true;
			from_l.set_markup("<b>From:</b> %s".printf(this.author));
			from_box.pack_start(from_l, false, false);

			star_i = new Image.from_pixbuf(STAR_EMPTY);
			var star_e = new EventBox();
			star_e.modify_bg(StateType.NORMAL, white);
			star_e.add(star_i);
			from_box.pack_start(star_e, false, false, 3);
			// On entering, change coloring to half. On exit return to the proper coloring.
			// If clicked, disable events, a signal will be received to finish the action.
			connect_signals(star_e, () => { return star_active; },
				// Enter
				() => {
					star_i.pixbuf = STAR_HALF;
				},
				// Leave
				() => {
					star_i.pixbuf = this.starred ? STAR_FULL : STAR_EMPTY;
				},
				// Press
				() => {
					star_active = false;
					star_clicked();
				}
			);

			important_i = new Image.from_pixbuf(IMPORTANT_EMPTY);
			var important_e = new EventBox();
			important_e.modify_bg(StateType.NORMAL, white);
			important_e.add(important_i);
			from_box.pack_start(important_e, false, false, 3);
			// On entering, change coloring to half. On exit return to the proper coloring.
			// If clicked, disable events, a signal will be received to finish the action.
			connect_signals(important_e, () => { return important_active; },
				// Enter
				() => {
					important_i.pixbuf = IMPORTANT_HALF;
				},
				// Leave
				() => {
					important_i.pixbuf = this.important ? IMPORTANT_FULL : IMPORTANT_EMPTY;
				},
				// Press
				() => {
					important_active = false;
					important_clicked();
				}
			);
			vbox.pack_start(from_box, false, false);

			// The actions : Mark read, archive, spam, delete
			// When mousing over an action, underline it.
			// When clicked, make it italic and disable all actions
			var actions_box = new Box(Orientation.HORIZONTAL, 0);
			ShouldAct should_act = () => { return actions_active; };
			var read_l = new Label(null);
			read_l.set_alignment(0, 0.5f);
			read_l.set_markup("<small><span foreground='darkred'>Mark as read</span> |</small>");
			var read_e = new EventBox();
			read_e.modify_bg(StateType.NORMAL, white);
			read_e.add(read_l);
			actions_box.pack_start(read_e, false, false);
			connect_signals(read_e, should_act,
				// Enter
				() => {
					read_l.set_markup("<small><u><span foreground='darkred'>Mark as read</span></u> |</small>");
				},
				// Leave
				() => {
					read_l.set_markup("<small><span foreground='darkred'>Mark as read</span> |</small>");
				},
				// Press
				() => {
					read_l.set_markup("<small><i><u><span foreground='darkred'>Marking as read...</span></u></i> |</small>");
					mark_read_clicked();
					actions_active = false;
				}
			);

			var archive_l = new Label(null);
			archive_l.set_alignment(0, 0.5f);
			archive_l.set_markup("<small> <span foreground='darkred'>Archive</span> |</small>");
			var archive_e = new EventBox();
			archive_e.modify_bg(StateType.NORMAL, white);
			archive_e.add(archive_l);
			actions_box.pack_start(archive_e, false, false);
			connect_signals(archive_e, should_act,
				// Enter
				() => {
					archive_l.set_markup("<small> <u><span foreground='darkred'>Archive</span></u> |</small>");
				},
				// Leave
				() => {
					archive_l.set_markup("<small> <span foreground='darkred'>Archive</span> |</small>");
				},
				// Press
				() => {
					archive_l.set_markup("<small> <i><u><span foreground='darkred'>Archiving...</span></u></i> |</small>");
					archive_clicked();
					actions_active = false;
				}
			);

			var spam_l = new Label(null);
			spam_l.set_alignment(0, 0.5f);
			spam_l.set_markup("<small> <span foreground='darkred'>Report spam</span> |</small>");
			var spam_e = new EventBox();
			spam_e.modify_bg(StateType.NORMAL, white);
			spam_e.add(spam_l);
			actions_box.pack_start(spam_e, false, false);
			connect_signals(spam_e, should_act,
				// Enter
				() => {
					spam_l.set_markup("<small> <u><span foreground='darkred'>Report spam</span></u> |</small>");
				},
				// Leave
				() => {
					spam_l.set_markup("<small> <span foreground='darkred'>Report spam</span> |</small>");
				},
				// Press
				() => {
					spam_l.set_markup("<small> <i><u><span foreground='darkred'>Reporting spam...</span></u></i> |</small>");
					spam_clicked();
					actions_active = false;
				}
			);

			var trash_l = new Label(null);
			trash_l.set_alignment(0, 0.5f);
			trash_l.set_markup("<small> <span foreground='darkred'>Delete</span></small>");
			var trash_e = new EventBox();
			trash_e.modify_bg(StateType.NORMAL, white);
			trash_e.add(trash_l);
			actions_box.pack_start(trash_e, false, false);
			connect_signals(trash_e, should_act,
				// Enter
				() => {
					trash_l.set_markup("<small> <u><span foreground='darkred'>Delete</span></u></small>");
				},
				// Leave
				() => {
					trash_l.set_markup("<small> <span foreground='darkred'>Delete</span></small>");
				},
				// Press
				() => {
					trash_l.set_markup("<small> <i><u><span foreground='darkred'>Deleting</span></u></i></small>");
					delete_clicked();
					actions_active = false;
				}
			);

			vbox.pack_start(actions_box, false, false, 1);

			// The message
			var summary_box = new Box(Orientation.HORIZONTAL, 0);
			var summary_l = new Label(null);
			summary_l.set_alignment(0, 0.5f);
			summary_l.wrap = true;
			summary_l.set_markup("<span foreground='grey25'>%s</span>".printf(this.summary));
			summary_box.pack_start(summary_l, false, false);
			vbox.pack_start(summary_box, false, false);

			visual = hbox;
			// Request our width so height calculations return correct answers.
			visual.width_request = 400;
		}

		/**
		 * Star the message, reactivate the star button
		 **/
		public void make_starred() {
			this.starred = true;
			this.star_active = true;
			this.star_i.pixbuf = STAR_FULL;
		}

		/**
		 * Unstar the message, reactivate the star button
		 **/
		public void make_unstarred() {
			this.starred = false;
			this.star_active = true;
			this.star_i.pixbuf = STAR_EMPTY;
		}

		/**
		 * Mark the message important, reactivate the button
		 **/
		public void make_important() {
			this.important = true;
			this.important_active = true;
			this.important_i.pixbuf = IMPORTANT_FULL;
		}

		/**
		 * Mark the message unimportant, reactivate the button
		 **/
		public void make_unimportant() {
			this.important = false;
			this.important_active = true;
			this.important_i.pixbuf = IMPORTANT_EMPTY;
		}

		/**
		 * Reactivate everything about this message.
		 * This is called in case of error so that we can try to act again.
		 **/
		public void reactivate() {
			this.actions_active = true;
			this.important_active = true;
			this.star_active = true;
		}
	}

	/**
	 * The Mailbox is a collection of MailItems. They are sorted by time received.
	 * Actions on the messages are made through the mailbox.
	 **/
	public class Mailbox : GLib.Object {
		/**
		 * The list has the messages in sorted order.
		 * the map allows for fast access of the desired message.
		 **/
		private Gee.List<MailItem> mail_list;
		private Gee.Map<string, MailItem> messages;

		/**
		 * Used to simplify repetetive actions on mail items
		 **/
		delegate void MessageAction(MailItem ma);

		/**
		 * Mailbox message count
		 **/
		public int size {
			get {
				return mail_list.size;
			}
		}

		/**
		 * Read only view of the mailbox in sorted order
		 **/
		public Gee.List<MailItem> items {
			owned get {
				return mail_list.read_only_view;
			}
		}

		public Mailbox() {
			this.mail_list = new ArrayList<MailItem>();
			this.messages = new HashMap<string, MailItem>();
		}

		/**
		 * Adds a message to the mailbox. Places the message at the proper place in the mail list.
		 **/
		public void add_message(MailItem m) {
			if(!messages.has_key(m.id)) {
				messages[m.id] = m;
				int i;
				for(i = 0; i < mail_list.size; i++) {
					if(mail_list[i].time.compare(m.time) < 0) {
						break;
					}
				}
				mail_list.insert(i, m);
			}
		}

		/**
		 * Gets the mail item with the given id
		 **/
		public new MailItem? get(string id) {
			if(messages.has_key(id)) {
				return messages[id];
			} else {
				return null;
			}
		}

		/**
		 * Removes the message with the given id
		 **/
		public void remove_message(string id) {
			if(messages.has_key(id)) {
				MailItem mess = null;
				messages.unset(id, out mess);
				mail_list.remove(mess);
				mess.remove_signals();
			}
		}

		/**
		 * Stars the message with the given id
		 **/
		public void star_message(string id) {
			message_action(id, (m) => { m.make_starred(); });
		}

		/**
		 * Unstars the message with the given id
		 **/
		public void unstar_message(string id) {
			message_action(id, (m) => { m.make_unstarred(); });
		}

		/**
		 * Marks a message important with the given id
		 **/
		public void important_message(string id) {
			message_action(id, (m) => { m.make_important(); });
		}

		/**
		 * Marks the message with the given id unimportant
		 **/
		public void unimportant_message(string id) {
			message_action(id, (m) => { m.make_unimportant(); });
		}

		/**
		 * Performs the given action on the mail item with the given id, if it exists
		 *
		 * @param id Id of the mail item to act on
		 * @param ma Action to perform on the mail item
		 **/
		private void message_action(string id, MessageAction ma) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				ma(mess);
			}
		}

		/**
		 * Reactivates all messages in the mailbox.
		 * This is called on error to ensure the mailbox is functional again.
		 **/
		public void reactivate_all() {
			foreach(var mess in mail_list) {
				mess.reactivate();
			}
		}
	}

}
