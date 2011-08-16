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


		}

		~MailItem() {
			stdout.printf("Mail Item destroyed\n");
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
