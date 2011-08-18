using Gee;
using Gtk;

namespace GmailFeed {

	public class MailItem : GLib.Object {
		public signal void mark_read_clicked();
		public signal void archive_clicked();
		public signal void spam_clicked();
		public signal void delete_clicked();
		public signal void star_clicked();
		public signal void important_clicked();

		public Widget visual {get; private set;}
		public string author {get; private set; default = "No Author";}
		public string subject {get; private set; default = "No Subject";}
		public string summary {get; private set; default = "";}
		public string id {get; private set; default = "";}
		public DateTime time {get; private set; default = new DateTime.now_local();}
		public bool starred {get; private set; default = false;}
		public bool important {get; private set; default = false;}

		private Gee.MultiMap<GLib.Object, ulong> signals;

		public MailItem(GMessage mess) {
			this.author = mess.author;
			this.subject = mess.subject;
			this.summary = mess.summary;
			this.id = mess.id;
			this.time = mess.time;
			this.starred = mess.starred;
			this.important = mess.important;

			this.signals = new Gee.HashMultiMap<GLib.Object, ulong>();

			create_visual();
		}

		internal void remove_signals() {
			foreach(var obj in signals.get_keys()) {
				foreach(var id in signals.get(obj)) {
					obj.disconnect(id);
				}
			}
			signals.clear();
		}

		private void create_visual() {
			Gdk.Color white;
			Gdk.Color.parse("#fff", out white);
			ulong sigid;

			var hbox = new HBox(false, 5);
			var vbox = new VBox(false, 0);
			hbox.pack_start(vbox, false, false, 5);

			var subject_box = new HBox(false, 0);
			var subject_l = new Label(null);
			subject_l.set_alignment(0, 0.5f);
			subject_l.wrap = true;
			subject_l.set_markup("<span foreground='#000'><b><u>%s</u></b></span>".printf(this.subject));
			var subject_e = new EventBox();
			subject_e.modify_bg(StateType.NORMAL, white);
			subject_e.add(subject_l);
			subject_box.pack_start(subject_e, false, false);
			vbox.pack_start(subject_box, false, false, 1);

			var from_box = new HBox(false, 0);
			var from_l = new Label(null);
			from_l.set_alignment(0, 0.5f);
			from_l.wrap = true;
			from_l.set_markup("<b>From:</b> %s".printf(this.author));
			from_box.pack_start(from_l, false, false);
			vbox.pack_start(from_box, false, false);

			var actions_box = new HBox(false, 0);
			var read_l = new Label(null);
			read_l.set_alignment(0, 0.5f);
			read_l.set_markup("<small><span foreground='darkred'>Mark as read</span> |</small>");
			var read_e = new EventBox();
			read_e.modify_bg(StateType.NORMAL, white);
			read_e.add(read_l);
			actions_box.pack_start(read_e, false, false);
			var re = read_e.enter_notify_event.connect(() => {
				read_l.set_markup("<small><u><span foreground='darkred'>Mark as read</span></u> |</small>");
				return false;
			});
			var rl = read_e.leave_notify_event.connect(() => {
				read_l.set_markup("<small><span foreground='darkred'>Mark as read</span> |</small>");
				return false;
			});
			sigid = read_e.button_press_event.connect(() => {
				read_l.set_markup("<small><i><u><span foreground='darkred'>Marking as read...</span></u></i> |</small>");
				read_e.disconnect(re);
				read_e.disconnect(rl);
				signals.remove(read_e, re);
				signals.remove(read_e, rl);
				mark_read_clicked();
				return false;
			});
			signals.set(read_e, re);
			signals.set(read_e, rl);
			signals.set(read_e, sigid);

			var archive_l = new Label(null);
			archive_l.set_alignment(0, 0.5f);
			archive_l.set_markup("<small> <span foreground='darkred'>Archive</span> |</small>");
			var archive_e = new EventBox();
			archive_e.modify_bg(StateType.NORMAL, white);
			archive_e.add(archive_l);
			actions_box.pack_start(archive_e, false, false);
			var ae = archive_e.enter_notify_event.connect(() => {
				archive_l.set_markup("<small> <u><span foreground='darkred'>Archive</span></u> |</small>");
				return false;
			});
			var al = archive_e.leave_notify_event.connect(() => {
				archive_l.set_markup("<small> <span foreground='darkred'>Archive</span> |</small>");
				return false;
			});
			sigid = archive_e.button_press_event.connect(() => {
				archive_l.set_markup("<small> <i><u><span foreground='darkred'>Archiving...</span></u></i> |</small>");
				archive_e.disconnect(ae);
				archive_e.disconnect(al);
				signals.remove(archive_e, ae);
				signals.remove(archive_e, al);
				archive_clicked();
				return false;
			});
			signals.set(archive_e, ae);
			signals.set(archive_e, al);
			signals.set(archive_e, sigid);

			var spam_l = new Label(null);
			spam_l.set_alignment(0, 0.5f);
			spam_l.set_markup("<small> <span foreground='darkred'>Report spam</span> |</small>");
			var spam_e = new EventBox();
			spam_e.modify_bg(StateType.NORMAL, white);
			spam_e.add(spam_l);
			actions_box.pack_start(spam_e, false, false);
			var se = spam_e.enter_notify_event.connect(() => {
				spam_l.set_markup("<small> <u><span foreground='darkred'>Report spam</span></u> |</small>");
				return false;
			});
			var sl = spam_e.leave_notify_event.connect(() => {
				spam_l.set_markup("<small> <span foreground='darkred'>Report spam</span> |</small>");
				return false;
			});
			sigid = spam_e.button_press_event.connect(() => {
				spam_l.set_markup("<small> <i><u><span foreground='darkred'>Reporting spam...</span></u></i> |</small>");
				spam_e.disconnect(se);
				spam_e.disconnect(sl);
				signals.remove(spam_e, se);
				signals.remove(spam_e, sl);
				spam_clicked();
				return false;
			});
			signals.set(spam_e, se);
			signals.set(spam_e, sl);
			signals.set(spam_e, sigid);

			var trash_l = new Label(null);
			trash_l.set_alignment(0, 0.5f);
			trash_l.set_markup("<small> <span foreground='darkred'>Delete</span></small>");
			var trash_e = new EventBox();
			trash_e.modify_bg(StateType.NORMAL, white);
			trash_e.add(trash_l);
			actions_box.pack_start(trash_e, false, false);
			var te = trash_e.enter_notify_event.connect(() => {
				trash_l.set_markup("<small> <u><span foreground='darkred'>Delete</span></u></small>");
				return false;
			});
			var tl = trash_e.leave_notify_event.connect(() => {
				trash_l.set_markup("<small> <span foreground='darkred'>Delete</span></small>");
				return false;
			});
			sigid = trash_e.button_press_event.connect(() => {
				trash_l.set_markup("<small> <i><u><span foreground='darkred'>Deleting</span></u></i></small>");
				trash_e.disconnect(te);
				trash_e.disconnect(tl);
				signals.remove(trash_e, te);
				signals.remove(trash_e, tl);
				delete_clicked();
				return false;
			});
			signals.set(trash_e, te);
			signals.set(trash_e, tl);
			signals.set(trash_e, sigid);


			vbox.pack_start(actions_box, false, false, 1);

			var summary_box = new HBox(false, 0);
			var summary_l = new Label(null);
			summary_l.set_alignment(0, 0.5f);
			summary_l.wrap = true;
			summary_l.set_markup("<span foreground='grey25'>%s</span>".printf(this.summary));
			summary_box.pack_start(summary_l, false, false);
			vbox.pack_start(summary_box, false, false);

			visual = hbox;
			visual.width_request = 400;
		}

		public void make_starred() {

		}

		public void make_unstarred() {

		}

		public void make_important() {

		}

		public void make_unimportant() {

		}
	}

	public class Mailbox : GLib.Object {
		private Gee.List<MailItem> mail_list;
		private Gee.Map<string, MailItem> messages;

		public int size {
			get {
				return mail_list.size;
			}
		}

		public Gee.List<MailItem> items {
			owned get {
				return mail_list.read_only_view;
			}
		}

		public Mailbox() {
			this.mail_list = new ArrayList<MailItem>();
			this.messages = new HashMap<string, MailItem>();
		}

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

		public new MailItem? get(string id) {
			if(messages.has_key(id)) {
				return messages[id];
			} else {
				return null;
			}
		}

		public void remove_message(string id) {
			if(messages.has_key(id)) {
				MailItem mess = null;
				messages.unset(id, out mess);
				mail_list.remove(mess);
				mess.remove_signals();
			}
		}

		public void star_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				mess.make_starred();
			}
		}

		public void unstar_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				mess.make_unstarred();
			}
		}

		public void important_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				mess.make_important();
			}
		}

		public void unimportant_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				mess.make_unimportant();
			}
		}
	}

}
