import 'dart:math' show pi;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lemmy_api_client/v2.dart';
import 'package:matrix4_transform/matrix4_transform.dart';

import '../hooks/delayed_loading.dart';
import '../hooks/infinite_scroll.dart';
import '../hooks/stores.dart';
import '../util/extensions/api.dart';
import '../util/extensions/datetime.dart';
import '../util/goto.dart';
import '../util/more_icon.dart';
import '../widgets/bottom_modal.dart';
import '../widgets/comment.dart';
import '../widgets/infinite_scroll.dart';
import '../widgets/info_table_popup.dart';
import '../widgets/markdown_text.dart';
import '../widgets/radio_picker.dart';
import '../widgets/sortable_infinite_list.dart';
import 'send_message.dart';

class InboxPage extends HookWidget {
  const InboxPage();

  @override
  Widget build(BuildContext context) {
    final accStore = useAccountsStore();
    final selected = useState(_SelectedAccount(
        accStore.defaultInstanceHost, accStore.defaultUsername));
    final theme = Theme.of(context);

    final isc1 = useInfiniteScrollController();
    final isc2 = useInfiniteScrollController();
    final isc3 = useInfiniteScrollController();
    final unreadOnly = useState(false);

    if (accStore.hasNoAccount) {
      return Scaffold(
        appBar: AppBar(),
        body: const Text('No accounts added'),
      );
    }

    void clear() {
      isc1.tryClear();
      isc2.tryClear();
      isc3.tryClear();
    }

    switchUnreadOnly() {
      unreadOnly.value = !unreadOnly.value;
      clear();
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: RadioPicker<_SelectedAccount>(
            onChanged: (val) {
              selected.value = val;
              clear();
            },
            title: 'select account',
            groupValue: selected.value,
            buttonBuilder: (context, displayString, onPressed) => TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 15),
              ),
              onPressed: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      displayString,
                      style: theme.appBarTheme.textTheme.headline6,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
            values: [
              for (final instance in accStore.loggedInInstances)
                for (final name in accStore.usernamesFor(instance))
                  _SelectedAccount(instance, name)
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(unreadOnly.value ? Icons.mail : Icons.mail_outline),
              onPressed: switchUnreadOnly,
            )
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Replies'),
              Tab(text: 'Mentions'),
              Tab(text: 'Messages'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SortableInfiniteList<CommentView>(
              controller: isc1,
              defaultSort: SortType.new_,
              fetcher: (page, batchSize, sortType) =>
                  LemmyApiV2(selected.value.instance).run(GetReplies(
                auth: accStore
                    .tokenFor(selected.value.instance, selected.value.name)
                    ?.raw,
                sort: sortType,
                limit: batchSize,
                page: page,
                unreadOnly: unreadOnly.value,
              )),
              itemBuilder: (cv) => CommentWidget.fromCommentView(cv),
            ),
            SortableInfiniteList<UserMentionView>(
              controller: isc2,
              defaultSort: SortType.new_,
              fetcher: (page, batchSize, sortType) =>
                  LemmyApiV2(selected.value.instance).run(GetUserMentions(
                auth: accStore
                    .tokenFor(selected.value.instance, selected.value.name)
                    ?.raw,
                sort: sortType,
                limit: batchSize,
                page: page,
                unreadOnly: unreadOnly.value,
              )),
              itemBuilder: (umv) => CommentWidget.fromUserMentionView(umv),
              // builder: ,
            ),
            InfiniteScroll<PrivateMessageView>(
              controller: isc3,
              // leading: ,
              fetcher: (page, batchSize) =>
                  LemmyApiV2(selected.value.instance).run(
                GetPrivateMessages(
                  auth: accStore
                      .tokenFor(selected.value.instance, selected.value.name)
                      ?.raw,
                  limit: batchSize,
                  page: page,
                  unreadOnly: unreadOnly.value,
                ),
              ),
              itemBuilder: (mv) =>
                  PrivateMessageTile(msg: mv, account: selected.value),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivateMessageTile extends HookWidget {
  final PrivateMessageView msg;
  final _SelectedAccount account;

  const PrivateMessageTile({@required this.msg, @required this.account});
  static const double _iconSize = 16;

  @override
  Widget build(BuildContext context) {
    final accStore = useAccountsStore();
    final theme = Theme.of(context);

    final raw = useState(false);
    final selectable = useState(false);
    final deleted = useState(msg.privateMessage.deleted);
    final deleteDelayed = useDelayedLoading(const Duration(milliseconds: 250));
    final read = useState(msg.privateMessage.read);
    final readDelayed = useDelayedLoading(const Duration(milliseconds: 200));
    final content = useState(msg.privateMessage.content);

    final toMe = _SelectedAccount(
            msg.recipient.originInstanceHost, msg.recipient.name) ==
        account;

    final otherSide = toMe ? msg.creator : msg.recipient;

    void showMoreMenu() {
      showBottomModal(
        context: context,
        builder: (context) {
          pop() => Navigator.of(context).pop();
          return Column(
            children: [
              if (raw.value)
                ListTile(
                  title: const Text('Show fancy'),
                  leading: const Icon(Icons.brush),
                  onTap: () {
                    raw.value = false;
                    pop();
                  },
                )
              else
                ListTile(
                  title: const Text('Show raw'),
                  leading: const Icon(Icons.build),
                  onTap: () {
                    raw.value = true;
                    pop();
                  },
                ),
              ListTile(
                title: Text('Make ${selectable.value ? 'un' : ''}selectable'),
                leading: Icon(
                    selectable.value ? Icons.assignment : Icons.content_cut),
                onTap: () {
                  selectable.value = !selectable.value;
                  pop();
                },
              ),
              ListTile(
                title: const Text('Nerd stuff'),
                leading: const Icon(Icons.info_outline),
                onTap: () {
                  pop();
                  showInfoTablePopup(context, msg.toJson());
                },
              ),
            ],
          );
        },
      );
    }

    Function() delayedAction<T>({
      @required DelayedLoading del,
      @required String instanceHost,
      @required LemmyApiQuery<T> Function() query,
      Function(T) onSuccess,
      Function(T) onFailure,
      Function(T) cleanup,
    }) {
      assert(del != null, 'required argument');
      assert(instanceHost != null, 'required argument');
      assert(query != null, 'required argument');

      return () async {
        T val;
        try {
          del.start();
          val = await LemmyApiV2(instanceHost).run(query());
          if (onSuccess != null) onSuccess(val);
          // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          Scaffold.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
          if (onFailure != null) onFailure(val);
        }
        if (cleanup != null) cleanup(val);
        del.cancel();
      };
    }

    final handleDelete = delayedAction<PrivateMessageView>(
      del: deleteDelayed,
      instanceHost: account.instance,
      query: () => DeletePrivateMessage(
        privateMessageId: msg.privateMessage.id,
        auth: accStore.tokenFor(account.instance, account.name)?.raw,
        deleted: !deleted.value,
      ),
      onSuccess: (_) => deleted.value = !deleted.value,
    );

    final handleRead = delayedAction<PrivateMessageView>(
      del: readDelayed,
      instanceHost: account.instance,
      query: () {
        print('mark as read');
        return MarkPrivateMessageAsRead(
          privateMessageId: msg.privateMessage.id,
          auth: accStore.tokenFor(account.instance, account.name)?.raw,
          read: !read.value,
        );
      },
      // TODO: add notification for notifying parent list
      onSuccess: (_) => read.value = !read.value,
    );

    final body = raw.value
        ? selectable.value
            ? SelectableText(content.value)
            : Text(content.value)
        : MarkdownText(
            content.value,
            instanceHost: msg.instanceHost,
            selectable: selectable.value,
          );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                toMe ? 'from ' : 'to ',
                style: TextStyle(color: theme.textTheme.caption.color),
              ),
              GestureDetector(
                onTap: () => goToUser.fromUserSafe(context, otherSide),
                child: Text(
                  otherSide.originDisplayName,
                  style: TextStyle(color: theme.accentColor),
                ),
              ),
              const Spacer(),
              if (msg.privateMessage.updated != null) const Text('🖊  '),
              Text(msg.privateMessage.updated?.fancy ??
                  msg.privateMessage.published.fancy),
              const SizedBox(width: 5),
              Transform(
                transform: Matrix4Transform()
                    .rotateByCenter((toMe ? -1 : 1) * pi / 2,
                        const Size(_iconSize, _iconSize))
                    .flipVertically(
                        origin: const Offset(_iconSize / 2, _iconSize / 2))
                    .matrix4,
                child: const Opacity(
                  opacity: 0.8,
                  child: Icon(Icons.reply, size: _iconSize),
                ),
              )
            ],
          ),
          const SizedBox(height: 5),
          if (msg.privateMessage.deleted)
            const Text('deleted by creator',
                style: TextStyle(fontStyle: FontStyle.italic))
          else
            body,
          Row(children: [
            const Spacer(),
            _Action(
              icon: moreIcon,
              onPressed: showMoreMenu,
              tooltip: 'more',
            ),
            if (toMe) ...[
              _Action(
                iconColor: read.value ? theme.accentColor : null,
                icon: Icons.check,
                tooltip: 'mark as read',
                onPressed: handleRead,
                delayedLoading: readDelayed,
              ),
              _Action(
                icon: Icons.reply,
                tooltip: 'reply',
                onPressed: () {
                  showCupertinoModalPopup(
                      context: context,
                      builder: (_) => SendMessagePage(
                            instanceHost: account.instance,
                            username: account.name,
                            recipient: otherSide,
                          ));
                },
              )
            ] else ...[
              _Action(
                icon: Icons.edit,
                tooltip: 'edit',
                onPressed: () async {
                  final pmv = await showCupertinoModalPopup<PrivateMessageView>(
                      context: context,
                      builder: (_) => SendMessagePage.edit(
                            msg,
                            instanceHost: account.instance,
                            username: account.name,
                            content: content.value,
                          ));
                  if (pmv != null) content.value = pmv.privateMessage.content;
                },
              ),
              _Action(
                delayedLoading: deleteDelayed,
                icon: deleted.value ? Icons.restore : Icons.delete,
                tooltip: 'delete',
                onPressed: handleDelete,
              ),
            ]
          ]),
          const Divider(),
        ],
      ),
    );
  }
}

@immutable
class _SelectedAccount {
  final String instance;
  final String name;

  const _SelectedAccount(this.instance, this.name);

  String toString() => '$name@$instance';

  @override
  bool operator ==(Object other) =>
      other is _SelectedAccount &&
      name == other.name &&
      instance == other.instance;

  @override
  int get hashCode => super.hashCode;
}

class _Action extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final DelayedLoading delayedLoading;
  final Color iconColor;

  const _Action({
    Key key,
    this.delayedLoading,
    this.iconColor,
    @required this.icon,
    @required this.onPressed,
    @required this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => IconButton(
        constraints: BoxConstraints.tight(const Size(36, 30)),
        icon: delayedLoading?.loading ?? false
            ? SizedBox.fromSize(
                size: const Size.square(22),
                child: const CircularProgressIndicator())
            : Icon(
                icon,
                color: iconColor ??
                    Theme.of(context).iconTheme.color.withAlpha(190),
              ),
        splashRadius: 25,
        onPressed: delayedLoading?.pending ?? false ? () {} : onPressed,
        iconSize: 25,
        tooltip: tooltip,
        padding: const EdgeInsets.all(0),
      );
}
