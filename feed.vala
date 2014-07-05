
using Soup;

namespace GmailFeed {

public class OAuthFields {
   public const string CLIENT_ID = "client_id";
   public const string CLIENT_SECRET = "client_secret";
   public const string REDIRECT_URI = "redirect_uri";
   public const string BEARER_TOKEN = "bearer_token";
   public const string REFRESH_TOKEN = "refresh_token";
}

public enum AuthError {
   SUCCESS,
   UNKNOWN,
   NEED_TOKEN,
   INVALID_AUTH,
   NEED_OAUTH_ID
}

public delegate AuthError AuthCodeDelegate(string authCode);

public class Feed : Object {
   public signal void newMessage(GMessage msg);
   public signal void updatedMessage(GMessage msg);
   public signal void messageStarred(string id);
   public signal void messageUnstarred(string id);

   /**
    * There is a generic message removed signal, along with signals for the specific
    * reason a message was removed. This is so you can act generally or specifically
    * without needing to duplicate excessive amounts of code.
    **/
   public signal void messageRemoved(string id);
   public virtual signal void messageRead(string id) {
      messageRemoved(id);
   }
   public virtual signal void messageArchived(string id) {
      messageRemoved(id);
   }
   public virtual signal void messageTrashed(string id) {
      messageRemoved(id);
   }
   public virtual signal void messageSpammed(string id) {
      messageRemoved(id);
   }

   /**
    * During an update several new messages might be added and other removed, this signal
    * indicates that all of those actions are complete so that you can act
    * once rather than many times.
    *
    * @param result: The error that the update completed with.
    **/
   public signal void updateComplete(AuthError result);

   private delegate void SuccessSignal(string msgId);

   public string address {get; private set;}

   private string? clientId;
   private string? clientSecret;
   private string? redirectUri;

   private string? bearerToken;
   private string? refreshToken;

   private Session       session;
   private Secret.Schema schema;

   private Gee.Map<string, GMessage> messages;

   public Gee.Collection<GMessage> inbox {
      owned get {
         return this.messages.values;
      }
   }

   public int count {
      get {
         return this.messages.size;
      }
   }

   public Feed(string address) {
      this.address = address;

      this.create_session();

      this.schema  = new Secret.Schema("org.wrowclif.gmailnotify", Secret.SchemaFlags.NONE,
                                       "address", Secret.SchemaAttributeType.STRING,
                                       "field",   Secret.SchemaAttributeType.STRING);

      this.messages = new Gee.HashMap<string, GMessage>();
   }

   public void loadInfo() {
      this.bearerToken = Secret.password_lookup_sync(this.schema, null,
                                                     "address", this.address,
                                                     "field", OAuthFields.BEARER_TOKEN);

      this.refreshToken = Secret.password_lookup_sync(this.schema, null,
                                                      "address", this.address,
                                                      "field", OAuthFields.REFRESH_TOKEN);

      this.clientId = Secret.password_lookup_sync(this.schema, null,
                                                  "address", this.address,
                                                  "field", OAuthFields.CLIENT_ID);

      this.clientSecret = Secret.password_lookup_sync(this.schema, null,
                                                      "address", this.address,
                                                      "field", OAuthFields.CLIENT_SECRET);

      this.redirectUri = Secret.password_lookup_sync(this.schema, null,
                                                     "address", this.address,
                                                     "field", OAuthFields.REDIRECT_URI);
   }

   public bool hasOAuthId() {
      return this.clientId != null;
   }

   public bool hasBearerToken() {
      return this.bearerToken != null;
   }

   private void create_session() {
      this.session = new SessionSync();
      this.session.timeout = 15;
   }

   public AuthError setOAuthInfo(string clientId, string clientSecret, string redirectUri) {
      var success = Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                                               "%s client ID".printf(this.address),
                                               clientId, null,
                                               "address", this.address,
                                               "field", OAuthFields.CLIENT_ID);

      success &= Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                                            "%s client secret".printf(this.address),
                                            clientSecret, null,
                                            "address", this.address,
                                            "field", OAuthFields.CLIENT_SECRET);

      success &= Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                                            "%s redirect_uri".printf(this.address),
                                            redirectUri, null,
                                            "address", this.address,
                                            "field", OAuthFields.REDIRECT_URI);

      if(success) {
         this.clientId = clientId;
         this.clientSecret = clientSecret;
         this.redirectUri = redirectUri;

         return AuthError.INVALID_AUTH;
      } else {
         this.clientId = null;
         this.clientSecret = null;
         this.redirectUri = null;

         return AuthError.NEED_OAUTH_ID;
      }
   }

   public string? getAuthUrl() {
      this.create_session();

      if(!this.hasOAuthId()) {
         return null;
      }

      var auth_addr = "https://accounts.google.com/o/oauth2/auth";

      var scope = "https://www.googleapis.com/auth/gmail.modify";

      var query = new HashTable<string, string>(str_hash, str_equal);

      query["redirect_uri"] = this.redirectUri;
      query["scope"] = scope;
      query["response_type"] = "code";
      query["client_id"] = this.clientId;

      var auth_uri = new Soup.URI(auth_addr);

      auth_uri.set_query_from_form(query);

      return auth_uri.to_string(false);
   }

   public AuthError setAuthCode(string authCode) {
      var token_addr = "https://accounts.google.com/o/oauth2/token";
      var token_msg  = new Message("POST", token_addr);

      var query = new HashTable<string, string>(str_hash, str_equal);

      query["code"] = authCode;
      query["client_id"] = this.clientId;
      query["client_secret"] = this.clientSecret;
      query["redirect_uri"] = this.redirectUri;
      query["grant_type"] = "authorization_code";
      var data = Form.encode_hash(query);

      token_msg.set_request("application/x-www-form-urlencoded", MemoryUse.COPY, data.data);

      session.send_message(token_msg);

      if(token_msg.status_code != 200) {
         if(token_msg.status_code == 401) {
            Secret.password_clear_sync(this.schema, null,
                                       "address", this.address,
                                       "field", OAuthFields.BEARER_TOKEN);

            Secret.password_clear_sync(this.schema, null,
                                       "address", this.address,
                                       "field", OAuthFields.REFRESH_TOKEN);
            this.bearerToken  = null;
            this.refreshToken = null;
         }

         return AuthError.NEED_OAUTH_ID;
      }

      var parser = new Json.Parser();
      parser.load_from_data((string) token_msg.response_body.data);

      var response = parser.get_root();

      var response_dict = response.get_object();

      var bearer_token  = response_dict.get_string_member("access_token");
      var refresh_token = response_dict.get_string_member("refresh_token");


      Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                                 "%s bearer token".printf(this.address),
                                 bearer_token, null,
                                 "address", this.address,
                                 "field", OAuthFields.BEARER_TOKEN);

      Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                                 "%s refresh token".printf(this.address),
                                 refresh_token, null,
                                 "address", this.address,
                                 "field", OAuthFields.REFRESH_TOKEN);

      this.bearerToken  = bearer_token;
      this.refreshToken = refresh_token;

      return AuthError.SUCCESS;
   }

   public AuthError refreshBearerToken() {
      this.create_session();

      if(!this.hasOAuthId()) {
         return AuthError.NEED_OAUTH_ID;
      } else if(this.refreshToken == null) {
         return AuthError.INVALID_AUTH;
      }

      var token_addr = "https://accounts.google.com/o/oauth2/token";
      var token_msg  = new Message("POST", token_addr);

      var query = new HashTable<string, string>(str_hash, str_equal);

      query["refresh_token"] = this.refreshToken;
      query["client_id"]     = this.clientId;
      query["client_secret"] = this.clientSecret;
      query["grant_type"]    = "refresh_token";

      var data = Form.encode_hash(query);

      token_msg.set_request("application/x-www-form-urlencoded", MemoryUse.COPY, data.data);

      session.send_message(token_msg);

      if(token_msg.status_code == 200) {
         var parser = new Json.Parser();
         parser.load_from_data((string) token_msg.response_body.data);

         var response = parser.get_root();

         var response_dict = response.get_object();

         this.bearerToken = response_dict.get_string_member("access_token");

         Secret.password_store_sync(this.schema, Secret.COLLECTION_DEFAULT,
                                    "%s bearer token".printf(this.address),
                                    this.bearerToken, null,
                                    "address", this.address,
                                    "field", OAuthFields.BEARER_TOKEN);

         return AuthError.SUCCESS;
      } else if(token_msg.status_code == 401) {
         Secret.password_clear_sync(this.schema, null,
                                    "address", this.address,
                                    "field", OAuthFields.BEARER_TOKEN);

         Secret.password_clear_sync(this.schema, null,
                                    "address", this.address,
                                    "field", OAuthFields.REFRESH_TOKEN);

         this.bearerToken  = null;
         this.refreshToken = null;

         return AuthError.INVALID_AUTH;
      }

      return AuthError.NEED_TOKEN;
   }

   public AuthError update() {
      AuthError result;

      if(!this.hasOAuthId()) {
         this.updateComplete(AuthError.NEED_OAUTH_ID);
         return AuthError.NEED_OAUTH_ID;
      }

      if(!this.hasBearerToken()) {
         result = this.refreshBearerToken();
         if(result != AuthError.SUCCESS) {
            this.updateComplete(result);
            return result;
         }
      }

      result = this.refreshInbox();

      if(result == AuthError.NEED_TOKEN) {
         result = this.refreshBearerToken();
         if(result != AuthError.SUCCESS) {
            this.updateComplete(result);
            return result;
         }

         result = this.refreshInbox();
      }

      this.updateComplete(result);
      return result;
   }

   public AuthError refreshInbox() {
      if(!this.hasBearerToken()) {
         return AuthError.NEED_TOKEN;
      }

      var inbox_msg = this.getUrl("/messages?labelIds=INBOX&q=is:unread");

      if(inbox_msg.status_code != 200) {
         if(inbox_msg.status_code == 401) {
            this.bearerToken = null;
            return AuthError.NEED_TOKEN;
         }
         return AuthError.UNKNOWN;
      }


      var parser = new Json.Parser();
      parser.load_from_data((string) inbox_msg.response_body.data);
      var root = parser.get_root();
      var inbox = root.get_object();

      var new_msgs = new Gee.HashSet<string>();

      if(inbox.has_member("messages")) {
         var msg_json = inbox.get_array_member("messages");

         for(uint idx = 0; idx < msg_json.get_length(); idx++) {
            var msg = msg_json.get_object_element(idx);

            var id = msg.get_string_member("id");

            new_msgs.add(id);
         }
      }

      var current_msgs = this.messages.keys;

      var to_add = new Gee.HashSet<string>();
      to_add.add_all(new_msgs);
      to_add.remove_all(current_msgs);

      var to_remove = new Gee.HashSet<string>();
      to_remove.add_all(current_msgs);
      to_remove.remove_all(new_msgs);

      var to_update = new Gee.HashSet<string>();
      to_update.add_all(current_msgs);
      to_update.retain_all(new_msgs);

      foreach(string msg_id in to_remove) {
         this.messages.unset(msg_id);
         this.messageRemoved(msg_id);
      }

      foreach(string msg_id in to_add) {
         var msg = new GMessage(msg_id);

         var request = this.getUrl("/messages/%s".printf(msg_id));

         if(request.status_code == 200) {
            var success = msg.fillDetails((string) request.response_body.data);

            if(success) {
               this.messages[msg_id] = msg;
               this.newMessage(msg);
            }
         }
      }

      foreach(string msg_id in to_update) {
         var msg = this.messages[msg_id];
         var request = this.getUrl("/messages/%s".printf(msg_id));

         if(request.status_code == 200) {
            var success = msg.fillDetails((string) request.response_body.data);

            if(success) {
               this.updatedMessage(msg);
            }
         }
      }


      return AuthError.SUCCESS;
   }

   public AuthError markRead(string msgId) {
      return this.modify(msgId, {}, {"UNREAD"}, (id) => {this.messageRead(id);});
   }

   public AuthError unstarMsg(string msgId) {
      if(! this.messages.has_key(msgId)) {
         return AuthError.UNKNOWN;
      }

      return this.modify(msgId, {}, {"STARRED"}, (id) => {this.messageUnstarred(id);});
   }

   public AuthError starMsg(string msgId) {
      if(! this.messages.has_key(msgId)) {
         return AuthError.UNKNOWN;
      }

      return this.modify(msgId, {"STARRED"}, {}, (id) => {this.messageStarred(id);});
   }

   public AuthError archive(string msgId) {
      return this.modify(msgId, {"ARCHIVED"}, {"INBOX"}, (id) => {this.messageArchived(id);});
   }

   public AuthError trash(string msgId) {
      return this.modify(msgId, {"TRASH"}, {"INBOX"}, (id) => {this.messageTrashed(id);});
   }

   public AuthError spam(string msgId) {
      return this.modify(msgId, {"SPAM"}, {"INBOX"}, (id) => {this.messageSpammed(id);});
   }

   private AuthError modify(string msgId, string[] addLabels, string[] removeLabels,
                            SuccessSignal successSignal) {
      if (this.bearerToken == null) {
         return AuthError.NEED_TOKEN;
      }

      if(!this.messages.has_key(msgId)) {
         return AuthError.UNKNOWN;
      }

      var modify_url = buildUrl("/messages/%s/modify".printf(msgId));

      var builder = new Json.Builder();

      builder.begin_object();
      builder.set_member_name("addLabelIds");
      builder.begin_array();
      foreach(var label in addLabels) {
         builder.add_string_value(label);
      }
      builder.end_array();

      builder.set_member_name("removeLabelIds");
      builder.begin_array();
      foreach(var label in removeLabels) {
         builder.add_string_value(label);
      }
      builder.end_array();

      builder.end_object();

      var generator = new Json.Generator();
      generator.set_root(builder.get_root());

      var data = generator.to_data(null);

      var modify_msg = new Soup.Message("POST", modify_url);

      modify_msg.request_headers.append("Authorization", "Bearer %s".printf(this.bearerToken));
      modify_msg.set_request("application/json", MemoryUse.COPY, data.data);

      session.send_message(modify_msg);

      if(modify_msg.status_code > 400) {
         if(modify_msg.status_code == 401) {
            this.bearerToken = null;
            return AuthError.NEED_TOKEN;
         }
         return AuthError.UNKNOWN;
      }

      successSignal(msgId);
      return AuthError.SUCCESS;
   }

   private string buildUrl(string end) {
      var base_addr = "https://www.googleapis.com/gmail/v1/users/me%s";

      return base_addr.printf(end);
   }

   private Message getUrl(string url) {
      var get_msg = new Message("GET", buildUrl(url));

      get_msg.request_headers.append("Authorization", "Bearer %s".printf(this.bearerToken));

      session.send_message(get_msg);

      return get_msg;
   }



}

public class GMessage : Object {
   public string author {get; private set; default = "No Author";}
   public string subject {get; private set; default = "No Subject";}
   public string summary {get; private set; default = "";}
   public string id {get; private set; default = "";}
   public string threadId {get; private set; default = "";}
   public DateTime time {get; private set; default = new DateTime.now_local();}

   public bool read {
      get {
         return ! ("INBOX" in this.labels);
      }
   }

   public bool starred {
      get {
         return "STARRED" in this.labels;
      }
   }

   private Gee.List<string> labels;

   public GMessage(string id) {
      this.id = id;

      this.labels = new Gee.ArrayList<string>();
   }

   public GMessage.copy(GMessage other) {
      this.author = other.author;
      this.subject = other.subject;
      this.summary = other.summary;
      this.id = other.id;
      this.threadId = other.threadId;
      this.time = other.time;

      this.labels = new Gee.ArrayList<string>();
      this.labels.add_all(other.labels);
   }

   public bool fillDetails(string detailsStr) {
      var parser = new Json.Parser();
      parser.load_from_data(detailsStr);
      var root = parser.get_root();
      var details = root.get_object();

      var id = details.get_string_member("id");

      if(id != this.id) {
         return false;
      }

      this.threadId = details.get_string_member("threadId");

      var payload = details.get_object_member("payload");
      var headers = payload.get_array_member("headers");

      var author_rx = /^(.*)<[^<>]+>$/;

      for(uint idx = 0; idx < headers.get_length(); idx++) {
         var header = headers.get_object_element(idx);

         var name = header.get_string_member("name").down();
         var val  = header.get_string_member("value");

         switch(name) {

            case "date" :
               this.time = parseDate(val);
               break;
            case "subject" :
               this.subject = val;
               break;
            case "from" :
               MatchInfo info;
               author_rx.match(val, 0, out info);
               if(info.fetch(0) != null) {
                  this.author = info.fetch(1).replace("\"", "");
               } else {
                  this.author = val;
               }
               break;
         }
      }

      this.summary = details.get_string_member("snippet");

      var labelIds = details.get_array_member("labelIds");

      this.labels.clear();

      for(uint idx = 0; idx < labelIds.get_length(); idx++) {
         this.labels.add(labelIds.get_string_element(idx));
      }

      return true;
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
      sb.append("\nID: ");
      sb.append(this.id);
      sb.append("\nLabels: ");
      foreach(string label in this.labels) {
         sb.append("%s, ".printf(label));
      }
      return sb.str;
   }

}

DateTime? parseDate(string dateTime) {
   //            "  Fri, 27      Jun     2014         22:     37:     25 -0500
   var format =
      /^[^0-9]*([^ ]+) ([^ ]+) ([^ ]+) ([^:]+):([^:]+):([^ ]+) ([+-]?[0-9]{4}|[a-zA-Z]{3,4})/;

   MatchInfo info = null;

   format.match(dateTime, 0, out info);

   if(info.fetch(0) == null) {
      return null;
   }

   int date         = int.parse(info.fetch(1));
   string month_str = info.fetch(2);
   int year         = int.parse(info.fetch(3));
   int hour         = int.parse(info.fetch(4));
   int minute       = int.parse(info.fetch(5));
   int second       = int.parse(info.fetch(6));
   string timezone  = info.fetch(7);

   //{ Parse the month using Time to decode the month string.
   //  Note: The time struct uses 0-based months. So add 1.
   var time = Time();
   time.strptime(month_str, "%b");
   int month = time.month + 1;
   //}

   var tz = new TimeZone(timezone);

   return new DateTime(tz, year, month, date, hour, minute, second);
}

}
