using Gee;

namespace GmailFeed {

	public class Mailbox : GLib.Object {
		private Gee.List<GMessage> mail_list;
		private Gee.Map<string, GMessage> messages;

		public int size {
			get {
				return mail_list.size;
			}
		}

		public Gee.List<GMessage> items {
			owned get {
				return mail_list.read_only_view;
			}
		}

		public Mailbox() {
			this.mail_list = new ArrayList<GMessage>();
			this.messages = new HashMap<string, GMessage>();
		}

		public void add_message(GMessage m) {
			if(!messages.has_key(m.id)) {
				messages[m.id] = m;
				mail_list.add(m);
				mail_list.sort((a,b) => {
					var aa = a as GMessage;
					var bb = b as GMessage;
					return bb.compare(aa);
				});
			}
		}

		public void remove_message(string id) {
			if(messages.has_key(id)) {
				GMessage mess = null;
				messages.unset(id, out mess);
				mail_list.remove(mess);
			}
		}

		public void star_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				if(!mess.starred) {
					mess.toggle_starred("");
				}
			}
		}

		public void unstar_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				if(mess.starred) {
					mess.toggle_starred("");
				}
			}
		}

		public void important_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				if(!mess.important) {
					mess.toggle_important("");
				}
			}
		}

		public void unimportant_message(string id) {
			if(messages.has_key(id)) {
				var mess = messages[id];
				if(mess.important) {
					mess.toggle_important("");
				}
			}
		}
	}

}
