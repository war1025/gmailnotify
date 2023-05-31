/*
 * Copyright © 2013 Wayne Rowcliffe <war1025@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 * Alternatively, you can redistribute and/or modify this program under the
 * same terms that the “gnome-shell” or “gnome-shell-extensions” software
 * packages are being distributed by The GNOME Project.
 *
 */

const St = imports.gi.St;
const Lang = imports.lang;
const Status = imports.ui.status;
const Panel = imports.ui.panel;
const PanelMenu = imports.ui.panelMenu;
const Main = imports.ui.main;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;

const GmailInstanceInterface = '<node>                                               \
                               <interface name="org.wrowclif.GmailNotify.Instance">  \
                                  <signal name="MessagesChanged" />                  \
                                  <method name="OpenMessageWindow" />                \
                                  <method name="GetMessageCount" >                   \
                                     <arg type="i" name="count" direction="out" />   \
                                  </method>                                          \
                               </interface>                                          \
                               </node>';

const GmailHubInterface      = '<node>                                                      \
                               <interface name="org.wrowclif.GmailNotify.Hub">              \
                                  <signal name="InstanceAdded" >                            \
                                     <arg type="(is)" name="newInstance" direction="out" /> \
                                  </signal>                                                 \
                                  <method name="GetInstanceList">                           \
                                     <arg type="a(is)" name="instances" direction="out" />  \
                                  </method>                                                 \
                               </interface>                                                 \
                               </node>';


let GmailInstanceProxy = Gio.DBusProxy.makeProxyWrapper(GmailInstanceInterface);
let GmailHubProxy      = Gio.DBusProxy.makeProxyWrapper(GmailHubInterface);

const GmailNotifyButton = new Lang.Class({
   Name: 'GmailNotifyButton',
   Extends: PanelMenu.Button,

   _init: function(instanceBus) {
      this.parent(0.25)

      this._notifyProxy = new GmailInstanceProxy(Gio.DBus.session,
                                                 instanceBus,
                                                 '/org/wrowclif/GmailNotify/Instance');

      let id1 = this._notifyProxy.connectSignal("MessagesChanged",
                                                Lang.bind(this, this._onMessagesChanged));
      let id2 = this._notifyProxy.connectSignal("ConnectedChanged",
                                                Lang.bind(this, this._onConnectedChanged));

      this.signalIds = [id1, id2];

      this.menu = {"toggle" : Lang.bind(this, this._openMessageWindow),
                   "destroy": function() {},
                   "connect": function() {}};

      this.icon = new St.Icon({style_class: 'system-status-icon'});

      this._onMessagesChanged();

      this.actor.add_actor(this.icon);

   },

   setIcon: function(iconName) {
      this.icon.icon_name = iconName;
   },

   _onMessagesChanged: function() {
      this._notifyProxy.GetMessageCountRemote(Lang.bind(this, function(message_count) {
            if(message_count > 0) {
               this.setIcon("gmailnotify");
            } else {
               this.setIcon("gmailnotify-empty");
            }
      }));
   },

   _onConnectedChanged: function(proxy, id, connected) {
      if(!connected[0]) {
         this.setIcon("gmailnotify-error");
      } else {
         this._onMessagesChanged();
      }
   },


   _openMessageWindow: function() {
      this._notifyProxy.OpenMessageWindowRemote();
   },

   shutdown: function() {
      for(let i = 0; i < this.signalIds.length; i++) {
         this._notifyProxy.disconnectSignal(this.signalIds[i]);
      }
      this._notifyProxy = null;
      this.signalIds = [];
      this.destroy();
   }
});

const GmailListener = new Lang.Class({
   Name: 'GmailListener',

   _init: function() {


      this._unwatchKey = Gio.DBus.watch_name(Gio.BusType.SESSION,
                                             "org.wrowclif.GmailNotify.Hub",
                                             Gio.BusNameWatcherFlags.NONE,
                                             Lang.bind(this, this._onHubConnected),
                                             Lang.bind(this, this._onHubDisconnected));

      this._hubProxy = null;

      this._instances = {};

   },

   _onHubConnected: function() {

      this._hubProxy = new GmailHubProxy(Gio.DBus.session,
                                         "org.wrowclif.GmailNotify.Hub",
                                         "/org/wrowclif/GmailNotify/Hub");

      this._hubProxy.connectSignal("InstanceAdded", Lang.bind(this, this._onClientsChanged));

      this._onClientsChanged();
   },

   _onHubDisconnected: function() {

      this._hubProxy = null;

      this._removeClients();
   },

   _onClientsChanged: function() {
      let instance_list = this._hubProxy.GetInstanceListSync()[0];

      for(let i = 0; i < instance_list.length; i++) {
         let instance = instance_list[i];

         if(!(instance[0] in this._instances)) {
            this._registerInstance(instance);
         }
      }
   },

   _registerInstance: function(instanceInfo) {
      let instance = new GmailNotifyButton(instanceInfo[1])

      this._instances[instanceInfo[0]] = instance;

      Main.panel.addToStatusArea(instanceInfo[1], instance);

      let unwatch_key = Gio.DBus.watch_name(Gio.BusType.SESSION,
                                            instanceInfo[1],
                                            Gio.BusNameWatcherFlags.NONE,
                                            function() {},
                                            Lang.bind(this, function() {
                                               instance.shutdown();
                                               delete this._instances[instanceInfo[0]];
                                               Gio.DBus.unwatch_name(unwatch_key);
                                            }));
   },

   _removeClients: function() {

      for(var id in this._instances) {
         this._instances[id].shutdown();
      }

      this._instances = {};

   }
});

let listener = null;

function init(meta) {
    // empty
}

function enable() {
   listener = new GmailListener();
}

function disable() {
   listener._removeClients();
   listener = null;
}
