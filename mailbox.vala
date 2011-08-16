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

		public MailItem(GMessage mess) {
			this.author = mess.author;
			this.subject = mess.subject;
			this.summary = mess.summary;
			this.id = mess.id;
			this.time = mess.time;
			this.starred = mess.starred;
			this.important = mess.important;

			create_visual();
		}

		~MailItem() {
			stdout.printf("Mail Item destroyed\n");
		}

		private void create_visual() {
			Gdk.Color white;
			Gdk.Color.parse("#fff", out white);

			var hbox = new HBox(false, 0);
			var vbox = new VBox(false, 0);
			hbox.pack_start(vbox, false, false);

			var subject_box = new HBox(false, 0);
			var subject_l = new Label(null);
			subject_l.wrap = true;
			subject_l.set_markup("<span foreground='#000'><b><u>%s</u></b></span>".printf(this.subject));
			var subject_e = new EventBox();
			subject_e.modify_bg(StateType.NORMAL, white);
			subject_e.add(subject_l);
			subject_box.pack_start(subject_e, false, false);
			vbox.pack_start(subject_box, false, false);

			var spacer = new HBox(false, 0);
			spacer.border_width = 1;
			vbox.pack_start(spacer, false, false);

			var from_box = new HBox(false, 0);
			var from_l = new Label(null);
			from_l.wrap = true;
			from_l.set_markup("<b>From:</b> %s".printf(this.author));
			from_box.pack_start(from_l, false, false);
			vbox.pack_start(from_box, false, false);

			var summary_box = new HBox(false, 0);
			var summary_l = new Label(null);
			summary_l.wrap = true;
			summary_l.set_markup("<span foreground='grey25'>%s</span>".printf(this.summary));
			summary_box.pack_start(summary_l, false, false);
			vbox.pack_start(summary_box, false, false);

			visual = hbox;
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
				mail_list.add(m);
				mail_list.sort((a,b) => {
					var aa = a as MailItem;
					var bb = b as MailItem;
					return bb.time.compare(aa.time);
				});
			}
		}

		public void remove_message(string id) {
			if(messages.has_key(id)) {
				MailItem mess = null;
				messages.unset(id, out mess);
				mail_list.remove(mess);
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
