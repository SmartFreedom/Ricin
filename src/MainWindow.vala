[GtkTemplate (ui="/chat/tox/Ricin/main-window.ui")]
public class Ricin.MainWindow : Gtk.ApplicationWindow {
  [GtkChild] public Gtk.Entry entry_name;
  [GtkChild] Gtk.Entry entry_status;
  [GtkChild] Gtk.Button button_user_status;
  [GtkChild] Gtk.Image image_user_status;
  [GtkChild] Gtk.ListBox friendlist;
  [GtkChild] Gtk.Label toxid;
  [GtkChild] Gtk.Stack chat_stack;
  [GtkChild] Gtk.Button button_add_friend_show;

  // Add friend revealer.
  [GtkChild] public Gtk.Revealer add_friend;
  [GtkChild] public Gtk.Entry entry_friend_id;
  [GtkChild] Gtk.TextView entry_friend_message;
  [GtkChild] Gtk.Label label_add_error;
  [GtkChild] Gtk.Button button_add_friend;
  [GtkChild] Gtk.Button button_cancel_add;

  // System notify.
  [GtkChild] public Gtk.Revealer revealer_system_notify;
  [GtkChild] public Gtk.Label label_system_notify;

  private ListStore friends = new ListStore (typeof (Tox.Friend));
  public Tox.Tox tox;

  public signal void notify_message (string message, int timeout = 5000);

  public MainWindow (Gtk.Application app, string profile) {
    Object (application: app);

    var opts = Tox.Options.create ();
    opts.ipv6_enabled = true;
    opts.udp_enabled = true;
    this.tox = new Tox.Tox (opts, profile);

    this.toxid.label += this.tox.id;
    this.entry_name.set_text (this.tox.username);
    this.entry_status.set_text (this.tox.status_message);
    this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/offline.png");

    this.button_add_friend_show.clicked.connect (() => {
      this.entry_friend_message.buffer.text = "Hello, I'm " + this.tox.username + ". Currently using Ricin, please add this friend request then we could talk!";
      this.button_add_friend_show.visible = false;
      this.label_add_error.visible = false;
      this.add_friend.reveal_child = true;
    });

    this.button_add_friend.clicked.connect (() => {
      var tox_id = this.entry_friend_id.get_text ();
      var message = this.entry_friend_message.buffer.text;
      var error_message = "";

      if (tox_id.length == ToxCore.ADDRESS_SIZE*2) { // bytes -> chars
        var friend = tox.add_friend (tox_id, message);
        this.entry_friend_id.set_text (""); // Clear the entry after adding a friend.
        return;
        //this.friends.append (friend);
      } else if (tox_id.index_of ("@") != -1) {
        error_message = "Ricin doesn't supports ToxDNS yet.";
      } else {
        error_message = "Invalid ToxID.";
      }

      if (error_message.strip () != "") {
        this.label_add_error.visible = true;
        this.label_add_error.set_text (error_message);
        return;
      }

      this.add_friend.reveal_child = false;
      this.button_add_friend_show.visible = true;
    });

    this.button_cancel_add.clicked.connect (() => {
      this.add_friend.reveal_child = false;
      this.button_add_friend_show.visible = true;
    });

    this.friendlist.bind_model (this.friends, fr => new FriendListRow (fr as Tox.Friend));
    this.friendlist.row_activated.connect ((lb, row) => {
      var fr = (row as FriendListRow).fr;
      foreach (var view in chat_stack.get_children ()) {
        if ((view as ChatView).fr == fr) {
          chat_stack.set_visible_child (view);
          (view as ChatView).entry.grab_focus ();
          (view as ChatView).focused = true;
          fr.unread_messages = false;
        }

        (view as ChatView).focused = false;
      }
    });

    this.entry_name.activate.connect (() => this.tox.username = Util.escape_html (this.entry_name.text));
    this.entry_status.bind_property ("text", this.tox, "status_message", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);

    this.button_user_status.clicked.connect (() => {
      var status = this.tox.status;
      switch (status) {
        case Tox.UserStatus.ONLINE:
          // Set status to away.
          this.tox.status = Tox.UserStatus.AWAY;
          this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/idle.png");
          break;
        case Tox.UserStatus.AWAY:
          // Set status to busy.
          this.tox.status = Tox.UserStatus.BUSY;
          this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/busy.png");
          break;
        case Tox.UserStatus.BUSY:
          // Set status to online.
          this.tox.status = Tox.UserStatus.ONLINE;
          this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/online.png");
          break;
        default:
          this.tox.status = Tox.UserStatus.OFFLINE;
          this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/offline.png");
          break;
      }
    });

    this.tox.notify["connected"].connect ((src, prop) => {
      if (this.tox.connected) {
        this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/online.png");
      } else {
        this.image_user_status.set_from_resource ("/chat/tox/Ricin/assets/status/offline.png");
      }
      this.button_user_status.sensitive = this.tox.connected;
    });

    this.tox.friend_request.connect ((id, message) => {
      var dialog = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "Friend request from:");
      dialog.secondary_text = @"$id\n\n$message";
      dialog.add_buttons ("Accept", Gtk.ResponseType.ACCEPT, "Reject", Gtk.ResponseType.REJECT);
      dialog.response.connect (response => {
        if (response == Gtk.ResponseType.ACCEPT) {
          var friend = tox.accept_friend_request (id);
          if (friend != null) {
            this.tox.save_data ();

            friends.append (friend);
            chat_stack.add_named (new ChatView (this.tox, friend), friend.name);

            var info_message = "The friend request has been accepted. Please wait the contact to appears online.";
            this.notify_message (@"<span color=\"#27ae60\">$info_message</span>", 5000);
          }
        }
        dialog.destroy ();
      });
      dialog.show ();
    });

    this.tox.friend_online.connect ((friend) => {
      if (friend != null) {
        friends.append (friend);
        chat_stack.add_named (new ChatView (this.tox, friend), friend.name);
      }
    });

    this.tox.friend_offline.connect ((friend) => {
      if (friend != null) {
        friend.status = Tox.UserStatus.OFFLINE;
      }
    });

    this.notify_message.connect ((message, timeout) =>  {
      this.label_system_notify.use_markup = true;
      this.label_system_notify.set_markup (message);
      this.revealer_system_notify.reveal_child = true;
      Timeout.add (timeout, () => {
        this.revealer_system_notify.reveal_child = false;
        return Source.REMOVE;
      });
    });

    this.delete_event.connect ((event) => {
      this.tox.save_data ();
      return false;
    });

    this.tox.run_loop ();

    this.show_all ();
  }
}
