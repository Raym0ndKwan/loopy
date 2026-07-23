export interface FakeContact {
  contactId: string;
  name: string;
  email: string;
}

export interface FakeEmailDraft {
  draftId: string;
  to: string;
  subject: string;
  body: string;
  eventTime: string;
}

export interface FakeSentMessage {
  messageId: string;
  draftId: string;
  to: string;
  subject: string;
  body: string;
}

export interface FakeHotel {
  hotelId: string;
  city: string;
  name: string;
  roomId: string;
  price: number;
  currency: string;
  score: number;
}

export interface FakePreparedBooking {
  bookingToken: string;
  hotelId: string;
  hotelName: string;
  roomId: string;
  checkIn: string;
  checkOut: string;
  price: number;
  currency: string;
  summary: string;
}

export interface FakeConfirmedBooking {
  bookingId: string;
  bookingToken: string;
  summary: string;
  status: 'confirmed';
}

function cloneContact(contact: FakeContact): FakeContact {
  return {
    contactId: contact.contactId,
    name: contact.name,
    email: contact.email
  };
}

function cloneDraft(draft: FakeEmailDraft): FakeEmailDraft {
  return {
    draftId: draft.draftId,
    to: draft.to,
    subject: draft.subject,
    body: draft.body,
    eventTime: draft.eventTime
  };
}

function cloneMessage(message: FakeSentMessage): FakeSentMessage {
  return {
    messageId: message.messageId,
    draftId: message.draftId,
    to: message.to,
    subject: message.subject,
    body: message.body
  };
}

function cloneHotel(hotel: FakeHotel): FakeHotel {
  return {
    hotelId: hotel.hotelId,
    city: hotel.city,
    name: hotel.name,
    roomId: hotel.roomId,
    price: hotel.price,
    currency: hotel.currency,
    score: hotel.score
  };
}

function clonePreparedBooking(booking: FakePreparedBooking): FakePreparedBooking {
  return {
    bookingToken: booking.bookingToken,
    hotelId: booking.hotelId,
    hotelName: booking.hotelName,
    roomId: booking.roomId,
    checkIn: booking.checkIn,
    checkOut: booking.checkOut,
    price: booking.price,
    currency: booking.currency,
    summary: booking.summary
  };
}

function cloneConfirmedBooking(booking: FakeConfirmedBooking): FakeConfirmedBooking {
  return {
    bookingId: booking.bookingId,
    bookingToken: booking.bookingToken,
    summary: booking.summary,
    status: 'confirmed'
  };
}

export class FakeWorldState {
  private readonly contacts: FakeContact[];
  private readonly hotels: FakeHotel[];
  private readonly drafts: Map<string, FakeEmailDraft> = new Map<string, FakeEmailDraft>();
  private readonly messages: FakeSentMessage[] = [];
  private readonly preparedBookings: Map<string, FakePreparedBooking> =
    new Map<string, FakePreparedBooking>();
  private readonly confirmedBookings: FakeConfirmedBooking[] = [];
  private draftSequence: number = 0;
  private messageSequence: number = 0;
  private bookingTokenSequence: number = 0;
  private bookingSequence: number = 0;

  constructor(
    contacts: FakeContact[] = FakeWorldState.defaultContacts(),
    hotels: FakeHotel[] = FakeWorldState.defaultHotels()
  ) {
    this.contacts = [];
    this.hotels = [];
    for (let index = 0; index < contacts.length; index++) {
      this.contacts.push(cloneContact(contacts[index]));
    }
    for (let index = 0; index < hotels.length; index++) {
      this.hotels.push(cloneHotel(hotels[index]));
    }
  }

  static defaultContacts(): FakeContact[] {
    return [
      {
        contactId: 'contact-001',
        name: '小王',
        email: 'xiaowang@example.com'
      },
      {
        contactId: 'contact-002',
        name: '小李',
        email: 'xiaoli@example.com'
      }
    ];
  }

  static defaultHotels(): FakeHotel[] {
    return [
      {
        hotelId: 'hotel-001',
        city: '杭州',
        name: '西湖实验酒店',
        roomId: 'room-101',
        price: 880,
        currency: 'CNY',
        score: 4.9
      },
      {
        hotelId: 'hotel-002',
        city: '杭州',
        name: '运河实验酒店',
        roomId: 'room-201',
        price: 620,
        currency: 'CNY',
        score: 4.6
      },
      {
        hotelId: 'hotel-003',
        city: '上海',
        name: '外滩实验酒店',
        roomId: 'room-301',
        price: 1080,
        currency: 'CNY',
        score: 4.8
      }
    ];
  }

  findContact(name: string): FakeContact | null {
    const normalized = name.trim().toLowerCase();
    for (let index = 0; index < this.contacts.length; index++) {
      const contact = this.contacts[index];
      if (contact.name.trim().toLowerCase() === normalized ||
        contact.email.trim().toLowerCase() === normalized) {
        return cloneContact(contact);
      }
    }
    return null;
  }

  createDraft(
    to: string,
    subject: string,
    body: string,
    eventTime: string
  ): FakeEmailDraft {
    this.draftSequence++;
    const draft: FakeEmailDraft = {
      draftId: this.identifier('draft', this.draftSequence),
      to,
      subject,
      body,
      eventTime
    };
    this.drafts.set(draft.draftId, cloneDraft(draft));
    return cloneDraft(draft);
  }

  findDraft(draftId: string): FakeEmailDraft | null {
    const draft = this.drafts.get(draftId);
    return draft === undefined ? null : cloneDraft(draft);
  }

  sendDraft(draftId: string): FakeSentMessage | null {
    const draft = this.drafts.get(draftId);
    if (draft === undefined) {
      return null;
    }
    this.messageSequence++;
    const message: FakeSentMessage = {
      messageId: this.identifier('message', this.messageSequence),
      draftId: draft.draftId,
      to: draft.to,
      subject: draft.subject,
      body: draft.body
    };
    this.messages.push(cloneMessage(message));
    return cloneMessage(message);
  }

  sentMessages(): FakeSentMessage[] {
    const values: FakeSentMessage[] = [];
    for (let index = 0; index < this.messages.length; index++) {
      values.push(cloneMessage(this.messages[index]));
    }
    return values;
  }

  searchHotels(city: string): FakeHotel[] {
    const normalized = city.trim().toLowerCase();
    const matches: FakeHotel[] = [];
    for (let index = 0; index < this.hotels.length; index++) {
      const hotel = this.hotels[index];
      if (hotel.city.trim().toLowerCase() === normalized) {
        matches.push(cloneHotel(hotel));
      }
    }
    matches.sort((left: FakeHotel, right: FakeHotel): number => right.score - left.score);
    return matches;
  }

  findHotel(hotelId: string): FakeHotel | null {
    for (let index = 0; index < this.hotels.length; index++) {
      if (this.hotels[index].hotelId === hotelId) {
        return cloneHotel(this.hotels[index]);
      }
    }
    return null;
  }

  prepareBooking(
    hotelId: string,
    roomId: string,
    checkIn: string,
    checkOut: string
  ): FakePreparedBooking | null {
    const hotel = this.findHotel(hotelId);
    if (hotel === null || hotel.roomId !== roomId) {
      return null;
    }
    this.bookingTokenSequence++;
    const booking: FakePreparedBooking = {
      bookingToken: this.identifier('booking-token', this.bookingTokenSequence),
      hotelId: hotel.hotelId,
      hotelName: hotel.name,
      roomId: hotel.roomId,
      checkIn,
      checkOut,
      price: hotel.price,
      currency: hotel.currency,
      summary: `${hotel.name} ${checkIn} 至 ${checkOut}，${hotel.price} ${hotel.currency}/晚`
    };
    this.preparedBookings.set(booking.bookingToken, clonePreparedBooking(booking));
    return clonePreparedBooking(booking);
  }

  findPreparedBooking(bookingToken: string): FakePreparedBooking | null {
    const booking = this.preparedBookings.get(bookingToken);
    return booking === undefined ? null : clonePreparedBooking(booking);
  }

  confirmBooking(bookingToken: string): FakeConfirmedBooking | null {
    const prepared = this.preparedBookings.get(bookingToken);
    if (prepared === undefined) {
      return null;
    }
    this.bookingSequence++;
    const confirmed: FakeConfirmedBooking = {
      bookingId: this.identifier('booking', this.bookingSequence),
      bookingToken,
      summary: prepared.summary,
      status: 'confirmed'
    };
    this.confirmedBookings.push(cloneConfirmedBooking(confirmed));
    return cloneConfirmedBooking(confirmed);
  }

  bookings(): FakeConfirmedBooking[] {
    const values: FakeConfirmedBooking[] = [];
    for (let index = 0; index < this.confirmedBookings.length; index++) {
      values.push(cloneConfirmedBooking(this.confirmedBookings[index]));
    }
    return values;
  }

  private identifier(prefix: string, sequence: number): string {
    const suffix = sequence.toString().padStart(3, '0');
    return `${prefix}-${suffix}`;
  }
}
