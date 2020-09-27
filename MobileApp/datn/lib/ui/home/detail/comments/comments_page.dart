import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:flutter_disposebag/flutter_disposebag.dart';
import 'package:flutter_provider/flutter_provider.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:loading_indicator/loading_indicator.dart';
import 'package:rx_redux/rx_redux.dart';

import '../../../../domain/model/comment.dart';
import '../../../../domain/model/user.dart';
import '../../../../domain/repository/comment_repository.dart';
import '../../../../domain/repository/user_repository.dart';
import '../../../../utils/utils.dart';
import '../../../app_scaffold.dart';
import '../../../widgets/empty_widget.dart';
import '../../../widgets/error_widget.dart';
import 'action.dart';
import 'add_comment/add_commen_page.dart';
import 'state.dart' as st;
import 'store.dart';

const imageSize = 54.0;

class CommentsPage extends StatefulWidget {
  final String movieId;

  const CommentsPage({Key key, @required this.movieId}) : super(key: key);

  @override
  _CommentsPageState createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage>
    with DisposeBagMixin, AutomaticKeepAliveClientMixin {
  RxReduxStore<Action, st.State> store;
  final commentDateFormat = DateFormat('dd/MM/yy');

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    store ??= () {
      final commentRepository = Provider.of<CommentRepository>(context);

      final getComments = ({
        @required int page,
        @required int perPage,
      }) =>
          commentRepository.getComments(
            movieId: widget.movieId,
            page: page,
            perPage: perPage,
          );

      final store = createStore(
        getComments,
        commentRepository.removeCommentById,
      );
      subscribe(store);
      store.dispatch(const LoadFirstPageAction());
      return store;
    }();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  void subscribe(RxReduxStore<Action, st.State> store) {
    store.stateStream
        .listen((state) => print('Page: ${state.page}'))
        .disposedBy(bag);

    store.actionStream.listen((action) {
      if (action is FailureAction) {
        context.showSnackBar(
          'Error occurred: ${getErrorMessage(action.error)}',
        );
      }
      if (action is SuccessAction) {
        if (action.comments.comments.isEmpty) {
          context.showSnackBar('Loaded all comments');
        }
      }
      if (action is RemoveCommentSuccess) {
        context.showSnackBar(
            'Removed successfully: ${action.comment.content.substring(0, 20)}...');
      }
      if (action is RemoveCommentFailure) {
        context.showSnackBar(
            'Failed when removing comment: ${action.comment.content.substring(0, 20)}...');
      }
    }).disposedBy(bag);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<st.State>(
      stream: store.stateStream,
      initialData: store.state,
      builder: (context, snapshot) {
        final state = snapshot.data;

        if (state.isLoading && state.isFirstPage) {
          return Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: LoadingIndicator(
                color: Theme.of(context).accentColor,
                indicatorType: Indicator.ballScaleMultiple,
              ),
            ),
          );
        }

        if (state.error != null && state.isFirstPage) {
          return Center(
            child: MyErrorWidget(
              errorText: 'Error: ${getErrorMessage(state.error)}',
              onPressed: () => store.dispatch(const RetryAction()),
            ),
          );
        }

        if (state.items.isEmpty) {
          return Center(
            child: EmptyWidget(
              message: 'Empty comments',
            ),
          );
        }

        return CommentItemsListWidget(
          state: state,
          dispatch: store.dispatch,
          commentDateFormat: commentDateFormat,
          movieId: widget.movieId,
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class CommentItemsListWidget extends StatelessWidget {
  final DateFormat commentDateFormat;
  final String movieId;

  const CommentItemsListWidget({
    Key key,
    @required this.state,
    @required this.dispatch,
    @required this.commentDateFormat,
    @required this.movieId,
  }) : super(key: key);

  final st.State state;
  final void Function(Action) dispatch;

  @override
  Widget build(BuildContext context) {
    final items = state.items;

    return ListView.separated(
      itemCount: 1 + items.length + (state.isFirstPage ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Header(
            average: state.average,
            total: state.total,
            movieId: movieId,
            dispatch: dispatch,
          );
        }

        index = index - 1;

        if (index < items.length) {
          final item = items[index];
          return CommentItemWidget(
            item: item,
            commentDateFormat: commentDateFormat,
            dispatch: dispatch,
          );
        }

        if (state.error != null) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: MyErrorWidget(
              errorText:
                  'Load page ${state.page}, error: ${getErrorMessage(state.error)}',
              onPressed: () => dispatch(const RetryAction()),
            ),
          );
        }

        if (state.isLoading) {
          return Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: LoadingIndicator(
                color: Theme.of(context).accentColor,
                indicatorType: Indicator.ballScaleMultiple,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Center(
            child: SizedBox(
              width: 128,
              height: 48,
              child: RaisedButton(
                onPressed: () => dispatch(const LoadNextPageAction()),
                child: Text('Next page'),
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 1,
                  ),
                ),
                color: Colors.white,
              ),
            ),
          ),
        );
      },
      separatorBuilder: (context, index) => const Divider(),
    );
  }
}

class CommentItemWidget extends StatelessWidget {
  final DateFormat commentDateFormat;
  final void Function(Action) dispatch;

  const CommentItemWidget({
    Key key,
    @required this.item,
    @required this.commentDateFormat,
    @required this.dispatch,
  }) : super(key: key);

  final Comment item;

  @override
  Widget build(BuildContext context) {
    final userRepo = Provider.of<UserRepository>(context);
    final optional = userRepo.user$.value;
    final isOwner = optional != null &&
        optional is Some<User> &&
        optional.value.uid == item.user.uid;

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).backgroundColor,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 16,
                        offset: Offset(2, 2),
                        color: Colors.grey.shade300,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: ClipOval(
                    child: item.user.avatar == null
                        ? Center(
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: imageSize * 0.7,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: item.user.avatar,
                            fit: BoxFit.cover,
                            width: imageSize,
                            height: imageSize,
                            progressIndicatorBuilder: (
                              BuildContext context,
                              String url,
                              progress,
                            ) {
                              return Center(
                                child: CircularProgressIndicator(
                                  value: progress.progress,
                                  strokeWidth: 2.0,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              );
                            },
                            errorWidget: (
                              BuildContext context,
                              String url,
                              dynamic error,
                            ) {
                              return Center(
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: imageSize * 0.7,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.user.fullName,
                        style: Theme.of(context)
                            .textTheme
                            .headline6
                            .copyWith(fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      IgnorePointer(
                        child: RatingBar(
                          initialRating: item.rate_star.toDouble(),
                          direction: Axis.horizontal,
                          itemCount: 5,
                          itemSize: 16,
                          itemBuilder: (context, _) => Icon(
                            Icons.star,
                            color: Colors.amber,
                          ),
                          onRatingUpdate: (_) {},
                          tapOnlyMode: true,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        commentDateFormat.format(item.createdAt),
                        style: Theme.of(context).textTheme.caption.copyWith(
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                            ),
                      ),
                    ],
                  ),
                ),
                if (isOwner)
                  IconButton(
                    icon: Icon(
                      Icons.delete,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => onRemovePressed(context),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.content,
              style:
                  Theme.of(context).textTheme.subtitle1.copyWith(fontSize: 13),
              textAlign: TextAlign.start,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> onRemovePressed(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Remove this comment'),
          content: Text(
              'Do you want to delete this comment. This action cannot be undone!'),
          actions: <Widget>[
            FlatButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            FlatButton(
              child: Text('OK'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (identical(ok, true)) {
      dispatch(RemoveCommentAction(item));
    }
  }
}

class Header extends StatelessWidget {
  final double average;
  final int total;
  final String movieId;
  final Function1<Action, void> dispatch;

  const Header({
    Key key,
    @required this.average,
    @required this.total,
    @required this.movieId,
    @required this.dispatch,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userRepo = Provider.of<UserRepository>(context);
    final avatar = userRepo.user$.value?.fold(() => null, (u) => u.avatar);

    return Column(
      children: [
        Card(
          elevation: 5,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: average.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.headline6.copyWith(
                              color: Colors.amber.shade800,
                              fontSize: 30,
                            ),
                      ),
                      TextSpan(
                        text: ' / 5',
                        style: Theme.of(context).textTheme.headline6.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: IgnorePointer(
                    child: RatingBar(
                      initialRating: average,
                      direction: Axis.horizontal,
                      itemCount: 5,
                      allowHalfRating: true,
                      itemSize: 32,
                      itemBuilder: (context, _) => Icon(
                        Icons.star,
                        color: Colors.amber,
                      ),
                      onRatingUpdate: (_) {},
                      tapOnlyMode: true,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Base on ',
                        style: Theme.of(context).textTheme.subtitle2,
                      ),
                      TextSpan(
                        text: total.toString(),
                        style: Theme.of(context).textTheme.headline6.copyWith(
                              fontSize: 24,
                              color: Theme.of(context).accentColor,
                            ),
                      ),
                      TextSpan(
                        text: ' reviews',
                        style: Theme.of(context).textTheme.subtitle2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () async {
            final comment = await AppScaffold.of(context).pushNamed(
              AddCommentPage.routeName,
              arguments: movieId,
            );
            if (comment != null) {
              dispatch(AddedCommentAction(comment));
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Container(
                  width: imageSize,
                  height: imageSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).backgroundColor,
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 16,
                        offset: Offset(2, 2),
                        color: Colors.grey.shade300,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: ClipOval(
                    child: avatar == null
                        ? Center(
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: imageSize * 0.7,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: avatar,
                            fit: BoxFit.cover,
                            width: imageSize,
                            height: imageSize,
                            progressIndicatorBuilder: (
                              BuildContext context,
                              String url,
                              progress,
                            ) {
                              return Center(
                                child: CircularProgressIndicator(
                                  value: progress.progress,
                                  strokeWidth: 2.0,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              );
                            },
                            errorWidget: (
                              BuildContext context,
                              String url,
                              dynamic error,
                            ) {
                              return Center(
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: imageSize * 0.7,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: imageSize * 0.8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(imageSize * 0.4),
                      color: Theme.of(context).buttonColor,
                    ),
                    child: Center(
                      child: Text('Your think about this movie?'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}