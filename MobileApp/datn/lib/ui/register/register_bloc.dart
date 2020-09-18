// ignore_for_file: close_sinks

import 'package:datn/domain/repository/user_repository.dart';
import 'package:datn/ui/register/register_state.dart';
import 'package:datn/utils/error.dart';
import 'package:datn/utils/streams.dart';
import 'package:datn/utils/type_defs.dart';
import 'package:datn/utils/validators.dart';
import 'package:flutter_bloc_pattern/flutter_bloc_pattern.dart';
import 'package:flutter_disposebag/flutter_disposebag.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

class RegisterBloc extends DisposeCallbackBaseBloc {
  /// Input functions
  final Function1<String, void> emailChanged;
  final Function1<String, void> passwordChanged;
  final Function0<void> submit;

  /// Streams
  final Stream<String> emailError$;
  final Stream<String> passwordError$;
  final Stream<RegisterMessage> message$;
  final Stream<bool> isLoading$;

  RegisterBloc._({
    @required Function0<void> dispose,
    @required this.emailChanged,
    @required this.passwordChanged,
    @required this.submit,
    @required this.emailError$,
    @required this.passwordError$,
    @required this.message$,
    @required this.isLoading$,
  }) : super(dispose);

  factory RegisterBloc(final UserRepository userRepository) {
    assert(userRepository != null);

    /// Controllers
    final emailController = PublishSubject<String>();
    final passwordController = PublishSubject<String>();
    final submitController = PublishSubject<void>();
    final isLoadingController = BehaviorSubject<bool>.seeded(false);
    final controllers = [
      emailController,
      passwordController,
      submitController,
      isLoadingController,
    ];

    ///
    /// Streams
    ///
    final isValidSubmit$ = Rx.combineLatest3(
      emailController.stream.map(Validator.isValidEmail),
      passwordController.stream.map(Validator.isValidPassword),
      isLoadingController.stream,
      (isValidEmail, isValidPassword, isLoading) =>
          isValidEmail && isValidPassword && !isLoading,
    ).shareValueSeeded(false);

    final credential$ = Rx.combineLatest2(
      emailController.stream,
      passwordController.stream,
      (email, password) => Credential(email: email, password: password),
    );

    final submit$ = submitController.stream
        .withLatestFrom(isValidSubmit$, (_, bool isValid) => isValid)
        .share();

    final message$ = Rx.merge([
      submit$
          .where((isValid) => isValid)
          .withLatestFrom(credential$, (_, Credential c) => c)
          .exhaustMap(
            (credential) => Rx.defer(() async* {
              await userRepository.register(
                credential.email,
                credential.password,
              );
              yield credential.email;
            })
                .doOnListen(() => isLoadingController.add(true))
                .doOnData((_) => isLoadingController.add(false))
                .doOnError((e, s) => isLoadingController.add(false))
                .map<RegisterMessage>((email) => RegisterSuccessMessage(email))
                .onErrorReturnWith(
                  (error) => RegisterErrorMessage(
                    'Register error: ${getErrorMessage(error)}',
                    error,
                  ),
                ),
          ),
      submit$
          .where((isValid) => !isValid)
          .map((_) => const InvalidInformationMessage())
    ]).share();

    final emailError$ = emailController.stream
        .map((email) {
          if (Validator.isValidEmail(email)) return null;
          return 'Invalid email address';
        })
        .distinct()
        .share();

    final passwordError$ = passwordController.stream
        .map((password) {
          if (Validator.isValidPassword(password)) return null;
          return 'Password must be at least 6 characters';
        })
        .distinct()
        .share();

    final subscriptions = <String, Stream>{
      'emailError': emailError$,
      'passwordError': passwordError$,
      'isValidSubmit': isValidSubmit$,
      'message': message$,
      'isLoading': isLoadingController,
    }.debug();

    return RegisterBloc._(
      dispose: DisposeBag([...controllers, ...subscriptions]).dispose,
      emailChanged: trim.pipe(emailController.add),
      passwordChanged: passwordController.add,
      submit: () => submitController.add(null),
      emailError$: emailError$,
      passwordError$: passwordError$,
      message$: message$,
      isLoading$: isLoadingController,
    );
  }
}