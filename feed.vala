using Soup;
using Gee;

namespace GmailFeed {

	public enum ConnectionError {
		UNAUTHORIZED,
		DISCONNECTED,
		UNKNOWN
	}

	public delegate string[] AuthDelegate();

	public class Feed : Object {
		public signal void new_message(GMessage msg);
		public signal void message_starred(string id);
		public signal void message_unstarred(string id);
		public signal void message_important(string id);
		public signal void message_unimportant(string id);
		public signal void message_removed(string id);
		public virtual signal void message_read(string id) {
			message_removed(id);
		}
		public virtual signal void message_archived(string id) {
			message_removed(id);
		}
		public virtual signal void message_trashed(string id) {
			message_removed(id);
		}
		public virtual signal void message_spammed(string id) {
			message_removed(id);
		}
		public signal void connection_error(ConnectionError code);
		public signal void login_success();
		public signal void update_complete();

		private Session session;
		private CookieJar cookiejar;
		private Gee.Map<string, GMessage> messages;
		private Gee.Map<string, GMessage> messages2;
		private string gmail_at;

		public int count {
			get {
				return messages.size;
			}
		}

		public Feed() {
			session = new SessionSync();
			cookiejar = new CookieJar();
			session.add_feature = cookiejar;
			session.timeout = 15;

			messages = new HashMap<string, GMessage>();
			messages2 = new HashMap<string, GMessage>();
			gmail_at = "";
		}

		public bool login(AuthDelegate ad) {
			var message = new Message("GET", "https://www.google.com/accounts/ServiceLogin?service=mail");
			session.send_message(message);

			gmail_at = "";
			var galx = "";

			SList<Cookie> cookies = cookiejar.all_cookies();
			for(int i = 0; i < cookies.length(); i++) {
				unowned Cookie c = cookies.nth_data(i);
				if(c.name == "GALX") {
					galx = URI.encode(c.value, null);
				}
			}

			message = new Message("POST", "https://www.google.com/accounts/ServiceLogin?service=mail");
			var p1 = "ltmpl=default&ltmplcache=2&continue=http://mail.google.com/mail/?ui%3Dhtml&service=mail&rm=false&scc=1&GALX=";
			var p2 ="&PersistentCookie=yes&rmShown=1&signIn=Sign+in&asts=";

			var at = ad();

			var post_body = "%s%s&Email=%s&Passwd=%s%s".printf(p1, galx, URI.encode(at[0], null), URI.encode(at[1], null), p2);

			message.set_request("application/x-www-form-urlencoded", MemoryUse.COPY, post_body.data);

			session.send_message(message);

			cookies = cookiejar.all_cookies();
			for(int i = 0; i < cookies.length(); i++) {
				unowned Cookie c = cookies.nth_data(i);
				if(c.name == "GMAIL_AT") {
					gmail_at = URI.encode(c.value, null);
				}
			}

			if(gmail_at != "") {
				login_success();
			} else {
				if(message.status_code == 200) {
					handle_error(401);
				} else {
					handle_error(message.status_code);
				}
			}
			return gmail_at != "";
		}

		public void update() {
			messages2.clear();
			var message = new Message("GET", "https://mail.google.com/mail/feed/atom");
			session.send_message(message);
			if(message.status_code != 200) {
				handle_error(message.status_code);
				return;
			}

			var body = (string) message.response_body.data;

			var messes = body.split("<entry>");

			messes = messes[1:messes.length];

			foreach(string s in messes) {
				var link = /<link.*\/>/;
				var href = /href=\".*\"/;
				var id = /message_id=.*&/;

				MatchInfo info = null;

				link.match(s, 0, out info);
				var sub = info.fetch(0);
				href.match(sub, 0, out info);
				sub = info.fetch(0);
				id.match(sub, 0, out info);
				sub = info.fetch(0);
				var mid = sub.substring(11, sub.index_of("&") - 11);

				if(messages.has_key(mid)) {
					messages2[mid] = messages[mid];
					continue;
				}

				int start = s.index_of("<name>") + 6;
				int end = s.index_of("</name>");
				var author = s.substring(start, end - start);

				start = s.index_of("<summary>") + 9;
				end = s.index_of("</summary>");
				var summary = s.substring(start, end - start);

				start = s.index_of("<title>") + 7;
				end = s.index_of("</title>");
				var subject = s.substring(start, end - start);

				start = s.index_of("<issued>") + 8;
				end = s.index_of("</issued>");
				sub = s.substring(start, end - start);

				var time = new DateTime.local(int.parse(sub.substring(0, 4)),
												int.parse(sub.substring(5, 2)),
												int.parse(sub.substring(8, 2)),
												int.parse(sub.substring(11, 2)),
												int.parse(sub.substring(14, 2)),
												int.parse(sub.substring(17, 2)));

				var gm = new GMessage(author, subject, summary, mid, time);

				messages2[mid] = gm;
				new_message(gm);

			}

			foreach(var k in messages.keys) {
				if(!messages2.has_key(k)) {
					message_read(k);
				}
			}

			var temp = messages;
			messages = messages2;
			messages2 = temp;

			update_complete();
		}

		public bool mark_read(string idx) {
			if(messages.has_key(idx)) {
				var mess = messages[idx].mark_read(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else {
					message_read(idx);
					return true;
				}
			}
			return false;
		}

		public bool toggle_important(string idx) {
			if(messages.has_key(idx)) {
				var m = messages[idx];
				var mess = m.toggle_important(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else if(m.important) {
					message_important(idx);
					return true;
				} else {
					message_unimportant(idx);
					return true;
				}
			}
			return false;
		}

		public bool toggle_starred(string idx) {
			if(messages.has_key(idx)) {
				var m = messages[idx];
				var mess = m.toggle_starred(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else if(m.starred) {
					message_starred(idx);
					return true;
				} else {
					message_unstarred(idx);
					return true;
				}
			}
			return false;
		}

		public bool archive(string idx) {
			if(messages.has_key(idx)) {
				var mess = messages[idx].archive(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else {
					message_archived(idx);
					return true;
				}
			}
			return false;
		}

		public bool trash(string idx) {
			if(messages.has_key(idx)) {
				var mess = messages[idx].trash(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else {
					message_trashed(idx);
					return true;
				}
			}
			return false;
		}

		public bool spam(string idx) {
			if(messages.has_key(idx)) {
				var mess = messages[idx].spam(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else {
					message_spammed(idx);
					return true;
				}
			}
			return false;
		}

		private void handle_error(uint code) {
			if(code == 401) {
				connection_error(ConnectionError.UNAUTHORIZED);
			} else if(code < 100) {
				connection_error(ConnectionError.DISCONNECTED);
			} else {
				connection_error(ConnectionError.UNKNOWN);
			}
		}

		public string to_string() {
			var sb = new StringBuilder();
			sb.append("Messages: %d\n\n".printf(messages.size));
			foreach(var m in messages.values) {
				sb.append(m.to_string());
				sb.append("\n\n\n");
			}
			return sb.str;
		}
	}


	public class GMessage : Object {
		public string author {get; private set; default = "No Author";}
		public string subject {get; private set; default = "No Subject";}
		public string summary {get; private set; default = "";}
		public string id {get; private set; default = "";}
		public DateTime time {get; private set; default = new DateTime.now_local();}
		public bool read {get; private set; default = false;}
		public bool starred {get; private set; default = false;}
		public bool important {get; private set; default = false;}

		public GMessage(string author, string subject, string summary, string id, DateTime time) {
			this.author = author;
			this.subject = subject;
			this.summary = summary;
			this.id = id;
			this.time = time;
		}

		public GMessage.copy(GMessage other) {
			this.author = other.author;
			this.subject = other.subject;
			this.summary = other.summary;
			this.id = other.id;
			this.time = other.time;

			this.read = other.read;
			this.starred = other.starred;
			this.important = other.important;
		}

		public string to_string() {
			var sb = new StringBuilder();
			sb.append("Author:  ");
			sb.append(this.author);
			sb.append("\nSubject: ");
			sb.append(this.subject);
			sb.append("\nSummary: ");
			sb.append(this.summary);
			sb.append("\nStarred: ");
			sb.append(this.starred ? "Yes" : "No");
			sb.append("\nImportant: ");
			sb.append(this.important ? "Yes" : "No");
			sb.append("\nID: ");
			sb.append(this.id);
			return sb.str;
		}

		public int compare(GMessage other) {
			return this.time.compare(other.time);
		}

		private Message act(string action, string gmail_at) {
			var message = new Message("POST", "%s%s%s%s%s".printf("https://mail.google.com/mail/?ik=ae2cd25c90&at=", gmail_at,
									"&view=up&act=", action, "&search=all"));

			var m_body = "t=%s".printf(this.id);

			message.set_request("application/x-www-form-urlencoded", MemoryUse.COPY, m_body.data);

			return message;
		}

		// Read -> rd
		// Star -> st
		// Unstar -> xst
		// Archive -> rc_%5Ei
		// Delete -> tr
		// Important -> mai
		// Not Important -> mani
		// Spam -> sp

		internal Message mark_read(string gmail_at) {
			this.read = true;
			return act("rd", gmail_at);
		}

		internal Message toggle_starred(string gmail_at) {
			var mess = act(starred ? "xst" : "st", gmail_at);
			this.starred = !this.starred;
			return mess;
		}

		internal Message toggle_important(string gmail_at) {
			var mess = act(important ? "mani" : "mai", gmail_at);
			this.important = !this.important;
			return mess;
		}

		internal Message archive(string gmail_at) {
			return act("rc_%5Ei", gmail_at);
		}

		internal Message trash(string gmail_at) {
			return act("tr", gmail_at);
		}

		internal Message spam(string gmail_at) {
			return act("sp", gmail_at);
		}
	}
}
