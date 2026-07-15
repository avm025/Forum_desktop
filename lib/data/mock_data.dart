import '../models/chat_type.dart';
import '../models/dialogs_list_view_model.dart';
import '../models/group_additional_info_model.dart';
import '../models/media_file.dart';
import '../models/message_emoji_model.dart';
import '../models/message_view_model.dart';

/// Демонстрационные данные, повторяющие наполнение макета "Форум".
class MockData {
  MockData._();

  static List<DialogsListViewModel> buildDialogs() {
    return [
      _nikolai(),
      _viktor(),
      _andrey(),
      _friends(),
      _tolya(),
      _alexander(),
      _wife(),
      _brother(),
      _aiAssistant(),
    ];
  }

  // --- Активный диалог из макета: Николай Бочкарев ---
  static DialogsListViewModel _nikolai() {
    return DialogsListViewModel(
      id: 'nikolai',
      usr_id: 'u_nikolai',
      avatar: '',
      avatarColor: ['#FF7A45', '#FF4D4F'],
      chatName: 'Николай Бочкарев',
      last_msg: 'Фотография',
      last_msg_fr_name: 'Николай Бочкарев',
      last_msg_dttmcr: '12:24',
      last_msg_status: 0,
      unread: 0,
      chatType: ChatType.privateChat,
      online: false,
      backgroundUrl: '',
      messages: [
        MessageViewModel(
          id: 'n1',
          type: 'text',
          fr_name: 'Николай Бочкарев',
          fr_id: 'u_nikolai',
          body: 'Че как дела?',
          text: 'Че как дела?',
          dtshow: '12:15',
          status: 2,
          showUserName: true,
          avaOnTop: true,
        ),
        MessageViewModel(
          id: 'n2',
          type: 'text',
          fr_name: 'Николай Бочкарев',
          fr_id: 'u_nikolai',
          body: 'Короткое сообщение в 2 строки, меньше максимума',
          text: 'Короткое сообщение в 2 строки, меньше максимума',
          dtshow: '12:16',
          status: 2,
        ),
        MessageViewModel(
          id: 'n3',
          type: 'text',
          fr_name: 'Николай Бочкарев',
          fr_id: 'u_nikolai',
          body:
              'Большой текст. Слова, предложения в определенной связи и '
              'последовательности, образующие какое-либо высказывание, '
              'сочинение, документ и т. д., напечатанные, написанные или '
              'запечатленные в памяти.',
          text: '',
          dtshow: '12:17',
          status: 2,
          avaOnBottom: true,
          emoji: [
            MessageEmojiModel(
              emoji: '👍',
              qty: 2,
              usrName: ['Толя', 'Жена'],
            ),
            MessageEmojiModel(emoji: '🔥', qty: 1, my: true, usrName: ['Вы']),
          ],
        ),
        MessageViewModel(
          id: 'n4',
          type: 'text',
          my: true,
          fr_name: 'Гангстер Космоса',
          body: 'Да всё ок',
          text: 'Да всё ок',
          dtshow: '12:22',
          status: 2,
          showUserName: true,
          avaOnTop: true,
        ),
        MessageViewModel(
          id: 'n5',
          type: 'text',
          my: true,
          fr_name: 'Гангстер Космоса',
          body: 'Здарова',
          text: 'Здарова',
          dtshow: '12:24',
          status: 0,
        ),
        MessageViewModel(
          id: 'n6',
          type: 'image',
          my: true,
          fr_name: 'Гангстер Космоса',
          body: '',
          text: '',
          dtshow: '12:24',
          status: 0,
          size: const MsgSize(248, 248),
          avaOnBottom: true,
          files: [
            MediaFile(
              hash: 'img1',
              kind: 'image',
              width: '248',
              height: '248',
              duration: 32,
            ),
          ],
        ),
      ],
    );
  }

  static DialogsListViewModel _viktor() {
    return DialogsListViewModel(
      id: 'viktor',
      avatar: '',
      avatarColor: ['#3B82F6', '#22D3EE'],
      chatName: 'Виктор',
      last_msg: 'Может быть',
      last_msg_fr_name: 'Виктор',
      last_msg_dttmcr: '14:04',
      last_msg_status: -2,
      unread: 1,
      chatMuted: true,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 'v1',
          type: 'text',
          fr_name: 'Виктор',
          body: 'Может быть',
          text: 'Может быть',
          dtshow: '14:04',
          status: 2,
          showUserName: true,
          avaOnTop: true,
          avaOnBottom: true,
        ),
      ],
    );
  }

  static DialogsListViewModel _andrey() {
    return DialogsListViewModel(
      id: 'andrey',
      avatar: '',
      avatarColor: ['#EC4899', '#F43F5E'],
      chatName: 'Андрей Москалёв',
      last_msg: '🇷🇺Россия Ответ на взрыв на Крымском мосту должен быть жёстк…',
      last_msg_fr_name: 'Андрей Москалёв',
      last_msg_dttmcr: 'вчера',
      last_msg_status: -2,
      unread: 0,
      fav: true,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 'a1',
          type: 'text',
          fr_name: 'Андрей Москалёв',
          body: '🇷🇺Россия Ответ на взрыв на Крымском мосту должен быть жёстким.',
          text: '🇷🇺Россия Ответ на взрыв на Крымском мосту должен быть жёстким.',
          dtshow: 'вчера',
          status: 2,
          showUserName: true,
          avaOnTop: true,
          avaOnBottom: true,
        ),
      ],
    );
  }

  static DialogsListViewModel _friends() {
    return DialogsListViewModel(
      id: 'friends',
      avatar: '',
      avatarColor: ['#22C55E', '#14B8A6'],
      chatName: 'Друзья',
      last_msg: 'Народ фотки с моря скидывать с…',
      last_msg_fr_name: 'Сергей Квасов',
      last_msg_dttmcr: 'пт',
      last_msg_status: -2,
      unread: 0,
      pin: 1,
      isGrp: true,
      chatType: ChatType.groupChat,
      groupAditionalInfo: GroupAditionalInfoModel(
        colAvalId: 12,
        desc: 'Лучшие друзья',
        nick: 'friends',
        isPublic: false,
        showRoles: true,
      ),
      messages: [
        MessageViewModel(
          id: 'f1',
          type: 'text',
          fr_name: 'Сергей Квасов',
          body: 'Народ фотки с моря скидывать сюда',
          text: 'Народ фотки с моря скидывать сюда',
          dtshow: 'пт',
          status: 2,
          showUserName: true,
          avaOnTop: true,
        ),
        MessageViewModel(
          id: 'f2',
          type: 'location',
          fr_name: 'Сергей Квасов',
          body: 'Геопозиция',
          text: '',
          dtshow: 'пт',
          status: 2,
          latitude: 44.6054,
          longitude: 33.5220,
          address: 'Севастополь, набережная',
          avaOnBottom: true,
        ),
      ],
    );
  }

  static DialogsListViewModel _tolya() {
    return DialogsListViewModel(
      id: 'tolya',
      avatar: '',
      avatarColor: ['#904FFF', '#5B36C9'],
      chatName: 'Толя',
      last_msg: 'Да я не знаю, завтра посмотрим',
      last_msg_fr_name: 'Толя',
      last_msg_dttmcr: '14:04',
      last_msg_status: -2,
      unread: 0,
      online: true,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 't1',
          type: 'text',
          fr_name: 'Толя',
          body: 'Да я не знаю, завтра посмотрим',
          text: 'Да я не знаю, завтра посмотрим',
          dtshow: '14:04',
          status: 2,
          showUserName: true,
          avaOnTop: true,
        ),
        MessageViewModel(
          id: 't2',
          type: 'text',
          my: true,
          fr_name: 'Вы',
          body: 'Ок, договорились',
          text: 'Ок, договорились',
          dtshow: '14:05',
          status: 1,
          avaOnBottom: true,
        ),
      ],
    );
  }

  static DialogsListViewModel _alexander() {
    return DialogsListViewModel(
      id: 'alexander',
      avatar: '',
      avatarColor: ['#06B6D4', '#3B82F6'],
      chatName: 'Александр Тимощенко',
      last_msg:
          'Баня заказана 8 окт, суббота в 20:00, с собой взять пиво и хорошее '
          'настроение,…',
      last_msg_fr_name: 'Вы',
      last_msg_dttmcr: '13:25',
      last_msg_status: 2,
      unread: 0,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 'al1',
          type: 'text',
          my: true,
          fr_name: 'Вы',
          body:
              'Баня заказана 8 окт, суббота в 20:00, с собой взять пиво и '
              'хорошее настроение, не опаздывать!',
          text:
              'Баня заказана 8 окт, суббота в 20:00, с собой взять пиво и '
              'хорошее настроение, не опаздывать!',
          dtshow: '13:25',
          status: 2,
          avaOnTop: true,
          avaOnBottom: true,
        ),
      ],
    );
  }

  static DialogsListViewModel _wife() {
    return DialogsListViewModel(
      id: 'wife',
      avatar: '',
      avatarColor: ['#22C55E', '#06B6D4'],
      chatName: 'Жена',
      last_msg: 'Я видел, да',
      last_msg_fr_name: 'Вы',
      last_msg_dttmcr: '22.08',
      last_msg_status: 1,
      unread: 0,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 'w1',
          type: 'text',
          fr_name: 'Жена',
          body: 'Купи хлеб по дороге',
          text: 'Купи хлеб по дороге',
          dtshow: '22.08',
          status: 2,
          showUserName: true,
          avaOnTop: true,
        ),
        MessageViewModel(
          id: 'w2',
          type: 'text',
          my: true,
          fr_name: 'Вы',
          body: 'Я видел, да',
          text: 'Я видел, да',
          dtshow: '22.08',
          status: 1,
          prn_id: 'w1',
          prn_body: 'Купи хлеб по дороге',
          prn_fr_name: 'Жена',
          prn_type: 'text',
          avaOnBottom: true,
        ),
      ],
    );
  }

  static DialogsListViewModel _brother() {
    return DialogsListViewModel(
      id: 'brother',
      avatar: '',
      avatarColor: ['#F59E0B', '#EF4444'],
      chatName: 'Братишка',
      last_msg: 'Голосовое сообщение',
      last_msg_fr_name: 'Братишка',
      last_msg_dttmcr: '22.08',
      last_msg_status: 2,
      unread: 0,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 'b1',
          type: 'voice',
          fr_name: 'Братишка',
          body: 'Голосовое сообщение',
          text: '',
          dtshow: '22.08',
          status: 2,
          showUserName: true,
          avaOnTop: true,
          avaOnBottom: true,
          voiceHistogram: const [
            3, 6, 9, 14, 18, 12, 8, 16, 22, 19, 11, 7, 13, 20, 24, 17, 10, 5,
            8, 12, 16, 9, 6, 4, 7, 11, 15, 19, 13, 8,
          ],
          files: [MediaFile(hash: 'voice1', kind: 'voice', duration: 14)],
        ),
      ],
    );
  }

  static DialogsListViewModel _aiAssistant() {
    return DialogsListViewModel(
      id: 'ai',
      ai: 1,
      avatar: '',
      avatarColor: ['#904FFF', '#3B82F6'],
      chatName: 'ИИ Ассистент',
      last_msg: 'Чем могу помочь сегодня?',
      last_msg_fr_name: 'ИИ Ассистент',
      last_msg_dttmcr: '09:30',
      last_msg_status: -2,
      unread: 0,
      chatType: ChatType.privateChat,
      messages: [
        MessageViewModel(
          id: 'ai1',
          type: 'text',
          ai: 1,
          fr_name: 'ИИ Ассистент',
          body: 'Чем могу помочь сегодня?',
          text: 'Чем могу помочь сегодня?',
          dtshow: '09:30',
          status: 2,
          showUserName: true,
          avaOnTop: true,
          avaOnBottom: true,
        ),
      ],
    );
  }
}
