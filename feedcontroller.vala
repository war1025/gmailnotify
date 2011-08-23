

namespace GmailFeed {

	/**
	 * Types of actions that we want the feed to perfom
	 **/
	internal enum FeedActionType {
		READ,
		STAR,
		IMPORTANT,
		ARCHIVE,
		SPAM,
		TRASH,
		UPDATE,
		LOGIN,
		QUIT
	}

	/**
	 * An action has an id for the message to act on and the type of action that should be taken
	 **/
	internal class FeedAction : GLib.Object {
		public string id {get; set; default = "";}
		public FeedActionType action {get; set;}
	}

	/**
	 * For the login action, we need an extra string for the password
	 **/
	internal class LoginAction : FeedAction {
		public string pass {get; set; default = "";}
	}

	/**
	 * FeedController exists because we need a way to separate the GUI thread and the message thread.
	 * We use an async queue to get actions to the message thread then use Idle callbacks to get response signals
	 * back on the GUI thread.
	 **/
	public class FeedController : GLib.Object {
		public signal void new_message(GMessage msg);
		public signal void message_starred(string id);
		public signal void message_unstarred(string id);
		public signal void message_important(string id);
		public signal void message_unimportant(string id);
		public signal void message_removed(string id);
		public signal void message_read(string id);
		public signal void message_archived(string id);
		public signal void message_trashed(string id);
		public signal void message_spammed(string id);
		public signal void login_success();
		public signal void connection_error(ConnectionError code);
		public signal void feed_closed();
		public signal void update_complete();

		/**
		 * Our feed object. The queue we use to go between threads, and the thread the feed runs on.
		 **/
		private Feed feed;
		private AsyncQueue<FeedAction> queue;
		private unowned Thread<void*> thread;

		/**
		 * Create the feed and the feed thread and start them running
		 **/
		public FeedController() {
			this.feed = new Feed();
			this.queue = new AsyncQueue<FeedAction>();

			connect_signals();

			try {
				this.thread = Thread.create<void*>(run, true);
			} catch(ThreadError e) {
				stderr.printf("Error starting thread\n");
			}

		}

		/**
		 * Take items off the queue, perform the specified action, repeat.
		 * Responses happen as signals so we don't need to worry about them here.
		 **/
		private void *run() {
			while(true) {
				var data = queue.pop();
				var s = data.id;
				switch(data.action) {
					case FeedActionType.READ : feed.mark_read(s); break;
					case FeedActionType.STAR : feed.toggle_starred(s); break;
					case FeedActionType.IMPORTANT : feed.toggle_important(s); break;
					case FeedActionType.ARCHIVE : feed.archive(s); break;
					case FeedActionType.SPAM : feed.spam(s); break;
					case FeedActionType.TRASH : feed.trash(s); break;
					case FeedActionType.UPDATE : feed.update(); break;
					case FeedActionType.LOGIN :
						LoginAction la = data as LoginAction;
						feed.login(() => {return {la.id, la.pass};});
						break;
					case FeedActionType.QUIT :
						Idle.add(() => {
							this.feed_closed();
							return false;
						});
						return null;
				}
			}
		}

		/**
		 * To shutdown we need to get the message thread to stop. We want to let any queued actions complete first though.
		 **/
		public void shutdown() {
			var act = new FeedAction();
			act.action = FeedActionType.QUIT;
			queue.push(act);
		}

		/**
		 * We need to get signals onto a different thread. We do this by adding Idle callbacks with the same content which
		 * will run on the GUI thread.
		 **/
		private void connect_signals() {
			this.feed.new_message.connect((m) => {
				Idle.add(() => {
					this.new_message(new GMessage.copy(m));
					return false;
				});
			});

			this.feed.message_starred.connect((m) => {
				Idle.add(() => {
					this.message_starred(m);
					return false;
				});
			});

			this.feed.message_unstarred.connect((m) => {
				Idle.add(() => {
					this.message_unstarred(m);
					return false;
				});
			});

			this.feed.message_important.connect((m) => {
				Idle.add(() => {
					this.message_important(m);
					return false;
				});
			});

			this.feed.message_unimportant.connect((m) => {
				Idle.add(() => {
					this.message_unimportant(m);
					return false;
				});
			});

			this.feed.message_archived.connect((m) => {
				Idle.add(() => {
					this.message_archived(m);
					return false;
				});
			});

			this.feed.message_trashed.connect((m) => {
				Idle.add(() => {
					this.message_trashed(m);
					return false;
				});
			});

			this.feed.message_spammed.connect((m) => {
				Idle.add(() => {
					this.message_spammed(m);
					return false;
				});
			});

			this.feed.message_read.connect((m) => {
				Idle.add(() => {
					this.message_read(m);
					return false;
				});
			});

			this.feed.message_removed.connect((m) => {
				Idle.add(() => {
					this.message_removed(m);
					return false;
				});
			});

			this.feed.login_success.connect(() => {
				Idle.add(() => {
					this.login_success();
					return false;
				});
			});

			this.feed.connection_error.connect((c) => {
				Idle.add(() => {
					this.connection_error(c);
					return false;
				});
			});

			this.feed.update_complete.connect(() => {
				Idle.add(() => {
					this.update_complete();
					return false;
				});
			});

		}

		/**
		 * These methods take care of getting the correct info into the queue to complete the desired actions.
		 **/
		public void update() {
			var act = new FeedAction();
			act.action = FeedActionType.UPDATE;
			queue.push(act);
		}

		public void mark_read(string id) {
			var act = new FeedAction();
			act.id = id;
			act.action = FeedActionType.READ;
			queue.push(act);
		}

		public void toggle_starred(string id) {
			var act = new FeedAction();
			act.id = id;
			act.action = FeedActionType.STAR;
			queue.push(act);
		}

		public void toggle_important(string id) {
			var act = new FeedAction();
			act.id = id;
			act.action = FeedActionType.IMPORTANT;
			queue.push(act);
		}

		public void archive(string id) {
			var act = new FeedAction();
			act.id = id;
			act.action = FeedActionType.ARCHIVE;
			queue.push(act);
		}

		public void trash(string id) {
			var act = new FeedAction();
			act.id = id;
			act.action = FeedActionType.TRASH;
			queue.push(act);
		}

		public void spam(string id) {
			var act = new FeedAction();
			act.id = id;
			act.action = FeedActionType.SPAM;
			queue.push(act);
		}

		public void login(AuthDelegate ad) {
			var creds = ad();
			var la = new LoginAction();
			la.id = creds[0];
			la.pass = creds[1];
			la.action = FeedActionType.LOGIN;
			queue.push(la);
		}

		/**
		 * Just a test main method, should probably be removed.
		 **/
		public static void main(string[] args) {
			var loop = new GLib.MainLoop();
			var feed = new FeedController();
			feed.new_message.connect((m) => {
				stdout.printf("%s\n\n", m.to_string());
				feed.toggle_important(m.id);
			});
			feed.message_important.connect((id) => {
				stdout.printf("Message: %s important\n", id);
				feed.toggle_important(id);
			});
			feed.message_unimportant.connect((id) => {
				stdout.printf("Message: %s unimportant\n", id);
				feed.toggle_starred(id);
			});
			feed.message_starred.connect((id) => {
				stdout.printf("Message: %s starred\n", id);
				feed.toggle_starred(id);
			});
			feed.message_unstarred.connect((id) => {
				stdout.printf("Message: %s unstarred\n", id);
				feed.mark_read(id);
			});
			feed.message_read.connect((id) => {
				stdout.printf("Message: %s read\n", id);
			});
			feed.login_success.connect(() => {
				stdout.printf("Logged in\n");
				feed.update();
			});
			feed.connection_error.connect((c) => {
				stdout.printf("Error Connecting: %s\n", c.to_string());
				stdout.printf("Hit Enter to attempt reconnecting: \n");
				stdin.read_line();
				feed.login(() => {return {args[1], args[3]};});
			});
			feed.login(() => {return {args[1], args[2]};});
			loop.run();
		}
	}
}

