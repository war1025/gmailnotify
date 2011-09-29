using Soup;
using Gee;

namespace GmailFeed {

	public enum ConnectionError {
		UNAUTHORIZED,
		DISCONNECTED,
		UNKNOWN
	}

	/**
	 * We want a username and password but we aren't picky about how we get it.
	 * Probably this is an unneccesary design step, but it doesn't hurt anything and gives some added flexibility.
	 **/
	public delegate string[] AuthDelegate();

	/**
	 * The Feed is what actually logs in, connects to the atom feed, and sends messages to gmail to take desired actions.
	 **/
	public class Feed : Object {
		public signal void new_message(GMessage msg);
		public signal void message_starred(string id);
		public signal void message_unstarred(string id);
		public signal void message_important(string id);
		public signal void message_unimportant(string id);
		/**
		 * There is a generic message removed signal, along with signals for the specific reason a message was removed.
		 * This is so you can act generally or specifically without needing to duplicate excessive amounts of code.
		 **/
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
		/**
		 * If an error occurs with the connection, we will send this signal.
		 **/
		public signal void connection_error(ConnectionError code);
		/**
		 * Notification that we have logged in successfully. You can't really do anything useful until you log in.
		 **/
		public signal void login_success();
		/**
		 * During an update several new messages might be added and other removed, this signal indicates that all of
		 * those actions are complete so that you can act once rather than many times.
		 **/
		public signal void update_complete();

		/**
		 * The session and cookies for our connection to gmail.
		 **/
		private Session session;
		private CookieJar cookiejar;
		/**
		 * Map message ids to GMessage objects. We have two maps so that we can do a swap and compare to see what is new
		 * and what we already have. This allows us to keep existing GMessages and not make new instances every time.
		 **/
		private Gee.Map<string, GMessage> messages;
		private Gee.Map<string, GMessage> messages2;
		/**
		 * This string is important for authentication when we are acting on messages
		 **/
		private string gmail_at;

		/**
		 * How many messages are in the feed
		 **/
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

		/**
		 * Log into gmail.
		 **/
		public bool login(AuthDelegate ad) {
			// Contact the login, this will give us the form info to submit
			var message = new Message("GET", "https://www.google.com/accounts/ServiceLogin?service=mail");
			message.request_headers.append("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/534.26+ (KHTML, like Gecko) Version/5.0 Safari/534.26+");

			session.send_message(message);

			if(message.status_code != 200) {
				handle_error(message.status_code);
				return false;
			}

			// Reset the gmail_at if it exists
			gmail_at = "";

			var cookies = cookiejar.all_cookies();
			for(int i = 0; i < cookies.length(); i++) {
				unowned Cookie c = cookies.nth_data(i);
				if(c.name == "GMAIL_AT") {
					cookiejar.delete_cookie(c);
				}
			}

			// Put all of our form data into this table so we can encode and submit it
			var table = new HashTable<string, string>(str_hash, str_equal);

			var form = /<form id=\"gaia_loginform\" action=\"([^\"]+)\".*<\/form>/;
			var inputx = /<input[^<>]+>/;
			var namex = /name=\"([^\"]+)\"/;
			var valx = /value=[\'\"]([^\'\"]*)[\'\"]/;

			var body = (string) message.response_body.data;

			body = body.replace("\n","");

			MatchInfo info = null;
			MatchInfo namei = null;
			MatchInfo vali = null;

			form.match(body, 0, out info);

			var gaiaform = info.fetch(0);
			var action = info.fetch(1);

			inputx.match(gaiaform, 0, out info);

			do {
				var field = info.fetch(0);
				namex.match(field, 0, out namei);
				valx.match(field, 0, out vali);

				var name = namei.fetch(1);
				var val = (vali.matches()) ? vali.fetch(1) : "";
				table.set(name, val);
			} while(info.next());

			// Run the authentication delegate to get our credentials.
			var at = ad();

			// Fill in login data, change the continue link so it goes to gmail
			table.set("Email", at[0]);
			table.set("Passwd", at[1]);
			table.set("continue", "http://mail.google.com/mail/?");

			var fm = Form.encode_hash(table);

			// Send the form
			message = new Message("POST", action);


			message.set_request("application/x-www-form-urlencoded", MemoryUse.COPY, fm.data);
			message.request_headers.append("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/534.26+ (KHTML, like Gecko) Version/5.0 Safari/534.26+");

			session.send_message(message);

			// Get our gmail_at cookie
			cookies = cookiejar.all_cookies();
			for(int i = 0; i < cookies.length(); i++) {
				unowned Cookie c = cookies.nth_data(i);
				if(c.name == "GMAIL_AT") {
					gmail_at = URI.encode(c.value, null);
				}
			}

			/**
			 * We have only logged in successfully if we have a gmail_at string
			 * Otherwise there was an error
			 **/
			if(gmail_at != "") {
				login_success();
			} else {
				// We get a 200 code even if we weren't authorized so change this to a 401 so we know the credentials were wrong.
				if(message.status_code == 200) {
					handle_error(401);
				} else {
					handle_error(message.status_code);
				}
			}
			return gmail_at != "";
		}

		/**
		 * Look at the feed, parse out the messages. Save any new messages. Remove any messages that aren't in the
		 * feed anymore.
		 **/
		public void update() {
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

			/**
			 * Here we check for messages that we used to have but that aren't in the feed anymore.
			 * These were removed by an outside source.
			 **/
			foreach(var k in messages.keys) {
				if(!messages2.has_key(k)) {
					message_removed(k);
				}
			}

			var temp = messages;
			messages = messages2;
			messages2 = temp;

			messages2.clear();

			update_complete();
		}

		/**
		 * Methods for acting on messages.
		 * Handles the sending of the message and success or error handling afterwards
		 **/
		public bool mark_read(string idx) {
			if(messages.has_key(idx)) {
				var mess = messages[idx].mark_read(gmail_at);
				session.send_message(mess);
				if(mess.status_code != 200) {
					handle_error(mess.status_code);
				} else {
					message_read(idx);
					messages.unset(idx);
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
					messages.unset(idx);
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
					messages.unset(idx);
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
					messages.unset(idx);
					return true;
				}
			}
			return false;
		}

		/**
		 * The methods above call this method so we can send an Error status based on the http status code we got.
		 **/
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


	/**
	 * GMessage tracks the state of a message while it is in our feed.
	 **/
	public class GMessage : Object {
		public string author {get; private set; default = "No Author";}
		public string subject {get; private set; default = "No Subject";}
		public string summary {get; private set; default = "";}
		public string id {get; private set; default = "";}
		public DateTime time {get; private set; default = new DateTime.now_local();}
		public bool read {get; private set; default = false;}
		public bool starred {get; private set; default = false;}
		public bool important {get; private set; default = false;}

		/**
		 * Construct a message from the relevant data.
		 **/
		public GMessage(string author, string subject, string summary, string id, DateTime time) {
			this.author = author;
			this.subject = subject;
			this.summary = summary;
			this.id = id;
			this.time = time;
		}

		/**
		 * Copy constructor
		 **/
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

		/**
		 * Comparable based on time received
		 **/
		public int compare(GMessage other) {
			return this.time.compare(other.time);
		}

		/**
		 * To act we need to send a post message with the proper action and gmail_at authentication parameters.
		 **/
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

		/**
		 * These methods construct a proper Soup Message for completing the desired action.
		 * The feed can then send the message it receives from the call and act on the response
		 **/
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
