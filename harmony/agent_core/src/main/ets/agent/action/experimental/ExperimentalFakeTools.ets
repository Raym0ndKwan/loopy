import { JsonValue } from '../ActionPlanTypes';
import { ExperimentalJsonSchema } from './ExperimentalJsonSchema';
import { ExperimentalToolRegistry } from './ExperimentalToolRegistry';
import {
  ExperimentalToolDefinition,
  ExperimentalToolErrorResult,
  ExperimentalToolExecutionContext,
  ExperimentalToolExecutionResult,
  ExperimentalToolExecutor,
  ExperimentalToolSuccessResult
} from './ExperimentalToolTypes';
import {
  FakeConfirmedBooking,
  FakeContact,
  FakeEmailDraft,
  FakeHotel,
  FakePreparedBooking,
  FakeSentMessage,
  FakeWorldState
} from './FakeWorldState';

export const LAB_DATE_RESOLVE: string = 'lab.date.resolve';
export const LAB_CONTACT_LOOKUP: string = 'lab.contact.lookup';
export const LAB_EMAIL_COMPOSE: string = 'lab.email.compose';
export const LAB_EMAIL_SEND: string = 'lab.email.send';
export const LAB_HOTEL_SEARCH: string = 'lab.hotel.search';
export const LAB_HOTEL_DETAIL: string = 'lab.hotel.detail';
export const LAB_HOTEL_BOOKING_PREPARE: string = 'lab.hotel.booking.prepare';
export const LAB_HOTEL_BOOKING_CONFIRM: string = 'lab.hotel.booking.confirm';
export const LAB_TOKEN_ISSUE: string = 'lab.token.issue';
export const LAB_TOKEN_CONSUME: string = 'lab.token.consume';

type ExperimentalArgValue = Object | string | number | boolean | null | undefined;
type ExperimentalArgs = Record<string, ExperimentalArgValue>;
type ExperimentalToolHandler = (
  args: Object,
  context: ExperimentalToolExecutionContext
) => Promise<ExperimentalToolExecutionResult>;

interface ExperimentalSchemaProperty {
  name: string;
  schema: ExperimentalJsonSchema;
}

interface LabDateResolveOutput {
  isoDateTime: string;
  displayText: string;
  timezone: string;
}

interface LabEmailSendOutput {
  messageId: string;
  draftId: string;
  status: string;
}

interface LabHotelSearchOutput {
  recommendedHotelId: string;
  recommendedHotelName: string;
  candidateCount: number;
  checkIn: string;
  checkOut: string;
}

interface LabHotelDetailOutput {
  hotelId: string;
  hotelName: string;
  roomId: string;
  price: number;
  currency: string;
  checkIn: string;
  checkOut: string;
}

interface LabHotelBookingPrepareOutput {
  bookingToken: string;
  summary: string;
  price: number;
  currency: string;
  status: string;
}

interface LabTokenIssueOutput {
  token: string;
}

interface LabTokenConsumeOutput {
  authorization: string;
  consumed: boolean;
}

class FunctionExperimentalToolExecutor implements ExperimentalToolExecutor {
  private readonly handler: ExperimentalToolHandler;

  constructor(handler: ExperimentalToolHandler) {
    this.handler = handler;
  }

  execute(
    args: Object,
    context: ExperimentalToolExecutionContext
  ): Promise<ExperimentalToolExecutionResult> {
    return this.handler(args, context);
  }
}

function success(output: JsonValue): ExperimentalToolSuccessResult {
  return {
    status: 'success',
    output
  };
}

function error(errorCode: string, message: string): ExperimentalToolErrorResult {
  return {
    status: 'error',
    errorCode,
    message
  };
}

function values(args: Object): ExperimentalArgs {
  return args as ExperimentalArgs;
}

function text(args: Object, key: string): string {
  const value = values(args)[key];
  return typeof value === 'string' ? value : '';
}

function stringSchema(description: string, minLength: number = 1): ExperimentalJsonSchema {
  return {
    type: 'string',
    description,
    minLength
  };
}

function numberSchema(description: string, minimum?: number): ExperimentalJsonSchema {
  const schema: ExperimentalJsonSchema = {
    type: 'number',
    description
  };
  if (minimum !== undefined) {
    schema.minimum = minimum;
  }
  return schema;
}

function integerSchema(description: string, minimum?: number): ExperimentalJsonSchema {
  const schema: ExperimentalJsonSchema = {
    type: 'integer',
    description
  };
  if (minimum !== undefined) {
    schema.minimum = minimum;
  }
  return schema;
}

function booleanSchema(description: string): ExperimentalJsonSchema {
  return {
    type: 'boolean',
    description
  };
}

function enumStringSchema(description: string, allowed: string[]): ExperimentalJsonSchema {
  const enumValues: JsonValue[] = [];
  for (let index = 0; index < allowed.length; index++) {
    enumValues.push(allowed[index]);
  }
  return {
    type: 'string',
    description,
    enum: enumValues
  };
}

function schemaProperty(
  name: string,
  schema: ExperimentalJsonSchema
): ExperimentalSchemaProperty {
  return {
    name,
    schema
  };
}

function objectSchema(
  description: string,
  propertyList: ExperimentalSchemaProperty[],
  required: string[]
): ExperimentalJsonSchema {
  const properties: Record<string, ExperimentalJsonSchema> = {};
  for (let index = 0; index < propertyList.length; index++) {
    properties[propertyList[index].name] = propertyList[index].schema;
  }
  return {
    type: 'object',
    description,
    properties,
    required,
    additionalProperties: false
  };
}

function twoDigits(value: number): string {
  return value < 10 ? `0${value}` : value.toString();
}

function dateParts(date: Date): string {
  return `${date.getUTCFullYear()}-${twoDigits(date.getUTCMonth() + 1)}-${twoDigits(date.getUTCDate())}`;
}

function resolvedHour(expression: string): number {
  const lower = expression.toLowerCase();
  if (expression.indexOf('下午') >= 0 || lower.indexOf('pm') >= 0) {
    if (expression.indexOf('三点') >= 0 || lower.indexOf('3') >= 0) {
      return 15;
    }
    return 14;
  }
  if (expression.indexOf('十点') >= 0 || lower.indexOf('10') >= 0) {
    return 10;
  }
  return 9;
}

function resolveNextMonday(
  expression: string,
  timezone: string,
  nowIso: string
): ExperimentalToolExecutionResult {
  if (timezone !== 'Asia/Shanghai') {
    return error('LAB_DATE_TIMEZONE_UNSUPPORTED', `Unsupported fake timezone: ${timezone}.`);
  }
  const normalized = expression.trim().toLowerCase();
  if (expression.indexOf('下周一') < 0 && normalized.indexOf('next monday') < 0) {
    return error(
      'LAB_DATE_EXPRESSION_UNSUPPORTED',
      'The fake date resolver currently supports 下周一 or next Monday.'
    );
  }
  const base = new Date(nowIso);
  if (Number.isNaN(base.getTime())) {
    return error('LAB_DATE_CLOCK_INVALID', 'Experimental execution context has an invalid nowIso.');
  }
  const day = base.getUTCDay();
  const daysUntilMonday = day === 1 ? 7 : (8 - day) % 7;
  base.setUTCDate(base.getUTCDate() + daysUntilMonday);
  const date = dateParts(base);
  const hour = resolvedHour(expression);
  const hourText = twoDigits(hour);
  const output: LabDateResolveOutput = {
    isoDateTime: `${date}T${hourText}:00:00+08:00`,
    displayText: `${date} ${hourText}:00`,
    timezone
  };
  return success(output);
}

function dateResolveDefinition(): ExperimentalToolDefinition {
  return {
    toolId: LAB_DATE_RESOLVE,
    revision: '1',
    name: '解析日期',
    description: 'Resolves a natural-language date expression against the injected clock. Returns an ISO date-time that later tools can consume.',
    riskLevel: 'read',
    inputSchema: objectSchema('Natural-language date request.', [
      schemaProperty('expression', stringSchema('Date expression such as 下周一上午九点.')),
      schemaProperty('timezone', enumStringSchema('IANA timezone used for the result.', ['Asia/Shanghai']))
    ], ['expression', 'timezone']),
    outputSchema: objectSchema('Resolved date-time.', [
      schemaProperty('isoDateTime', stringSchema('ISO date-time accepted by downstream tools.')),
      schemaProperty('displayText', stringSchema('Human-readable date-time.')),
      schemaProperty('timezone', stringSchema('Timezone used to resolve the expression.'))
    ], ['isoDateTime', 'displayText', 'timezone']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      return resolveNextMonday(text(args, 'expression'), text(args, 'timezone'), context.nowIso);
    })
  };
}

function contactLookupDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_CONTACT_LOOKUP,
    revision: '1',
    name: '查询联系人',
    description: 'Looks up one contact by exact name or email in the deterministic fake address book. Returns an email address for later mail tools.',
    riskLevel: 'read',
    inputSchema: objectSchema('Contact lookup request.', [
      schemaProperty('name', stringSchema('Exact contact name or email address.'))
    ], ['name']),
    outputSchema: objectSchema('Resolved contact.', [
      schemaProperty('contactId', stringSchema('Stable fake contact identifier.')),
      schemaProperty('name', stringSchema('Contact display name.')),
      schemaProperty('email', stringSchema('Email address accepted by lab.email.compose.'))
    ], ['contactId', 'name', 'email']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const contact: FakeContact | null = world.findContact(text(args, 'name'));
      return contact === null ?
        error('LAB_CONTACT_NOT_FOUND', 'No fake contact matched the requested name.') :
        success(contact);
    })
  };
}

function emailComposeDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_EMAIL_COMPOSE,
    revision: '1',
    name: '生成邮件草稿',
    description: 'Creates a fake email draft but does not send it. Returns draftId, which is the required input of lab.email.send.',
    riskLevel: 'draft',
    inputSchema: objectSchema('Email drafting request.', [
      schemaProperty('to', stringSchema('Recipient email, normally from lab.contact.lookup.')),
      schemaProperty('subject', stringSchema('Email subject.')),
      schemaProperty('eventTime', stringSchema('ISO event time, normally from lab.date.resolve.')),
      schemaProperty('instructions', stringSchema('Natural-language instructions for the email body.'))
    ], ['to', 'subject', 'eventTime', 'instructions']),
    outputSchema: objectSchema('Created fake email draft.', [
      schemaProperty('draftId', stringSchema('Draft identifier accepted by lab.email.send.')),
      schemaProperty('to', stringSchema('Resolved recipient email.')),
      schemaProperty('subject', stringSchema('Draft subject.')),
      schemaProperty('body', stringSchema('Generated deterministic body.')),
      schemaProperty('eventTime', stringSchema('Event time included in the draft.'))
    ], ['draftId', 'to', 'subject', 'body', 'eventTime']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const to = text(args, 'to');
      const subject = text(args, 'subject');
      const eventTime = text(args, 'eventTime');
      const instructions = text(args, 'instructions');
      const body = `${instructions}\n时间：${eventTime}`;
      const draft: FakeEmailDraft = world.createDraft(to, subject, body, eventTime);
      return success(draft);
    })
  };
}

function emailSendDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_EMAIL_SEND,
    revision: '1',
    name: '发送邮件',
    description: 'Sends a draft previously created by lab.email.compose into the isolated fake outbox. It requires the returned draftId and has a simulated external side effect.',
    riskLevel: 'confirm_required',
    inputSchema: objectSchema('Fake email send request.', [
      schemaProperty('draftId', stringSchema('Draft identifier returned by lab.email.compose.'))
    ], ['draftId']),
    outputSchema: objectSchema('Fake send result.', [
      schemaProperty('messageId', stringSchema('Stable fake sent-message identifier.')),
      schemaProperty('draftId', stringSchema('Source draft identifier.')),
      schemaProperty('status', enumStringSchema('Fake delivery status.', ['sent']))
    ], ['messageId', 'draftId', 'status']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const sent: FakeSentMessage | null = world.sendDraft(text(args, 'draftId'));
      if (sent === null) {
        return error('LAB_EMAIL_DRAFT_NOT_FOUND', 'The requested fake draft does not exist.');
      }
      const output: LabEmailSendOutput = {
        messageId: sent.messageId,
        draftId: sent.draftId,
        status: 'sent'
      };
      return success(output);
    })
  };
}

function hotelSearchDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_HOTEL_SEARCH,
    revision: '1',
    name: '搜索酒店',
    description: 'Searches deterministic fake hotels and returns the highest-scored match as recommendedHotelId. Use that id with lab.hotel.detail.',
    riskLevel: 'read',
    inputSchema: objectSchema('Fake hotel search request.', [
      schemaProperty('city', stringSchema('Destination city.')),
      schemaProperty('checkIn', stringSchema('Check-in date in YYYY-MM-DD form.')),
      schemaProperty('checkOut', stringSchema('Check-out date in YYYY-MM-DD form.')),
      schemaProperty('preference', stringSchema('Natural-language hotel preference.'))
    ], ['city', 'checkIn', 'checkOut', 'preference']),
    outputSchema: objectSchema('Recommended fake hotel.', [
      schemaProperty('recommendedHotelId', stringSchema('Hotel id accepted by lab.hotel.detail.')),
      schemaProperty('recommendedHotelName', stringSchema('Recommended hotel name.')),
      schemaProperty('candidateCount', integerSchema('Number of matching fake hotels.', 1)),
      schemaProperty('checkIn', stringSchema('Requested check-in date.')),
      schemaProperty('checkOut', stringSchema('Requested check-out date.'))
    ], ['recommendedHotelId', 'recommendedHotelName', 'candidateCount', 'checkIn', 'checkOut']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const hotels: FakeHotel[] = world.searchHotels(text(args, 'city'));
      if (hotels.length === 0) {
        return error('LAB_HOTEL_NOT_FOUND', 'No fake hotel matched the requested city.');
      }
      const output: LabHotelSearchOutput = {
        recommendedHotelId: hotels[0].hotelId,
        recommendedHotelName: hotels[0].name,
        candidateCount: hotels.length,
        checkIn: text(args, 'checkIn'),
        checkOut: text(args, 'checkOut')
      };
      return success(output);
    })
  };
}

function hotelDetailDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_HOTEL_DETAIL,
    revision: '1',
    name: '读取酒店详情',
    description: 'Loads one deterministic fake hotel by hotelId. Returns roomId and price for lab.hotel.booking.prepare.',
    riskLevel: 'read',
    inputSchema: objectSchema('Fake hotel detail request.', [
      schemaProperty('hotelId', stringSchema('Hotel id returned by lab.hotel.search.')),
      schemaProperty('checkIn', stringSchema('Check-in date.')),
      schemaProperty('checkOut', stringSchema('Check-out date.'))
    ], ['hotelId', 'checkIn', 'checkOut']),
    outputSchema: objectSchema('Fake hotel detail.', [
      schemaProperty('hotelId', stringSchema('Hotel identifier.')),
      schemaProperty('hotelName', stringSchema('Hotel name.')),
      schemaProperty('roomId', stringSchema('Room id accepted by lab.hotel.booking.prepare.')),
      schemaProperty('price', numberSchema('Nightly fake room price.', 0)),
      schemaProperty('currency', stringSchema('Price currency.')),
      schemaProperty('checkIn', stringSchema('Check-in date.')),
      schemaProperty('checkOut', stringSchema('Check-out date.'))
    ], ['hotelId', 'hotelName', 'roomId', 'price', 'currency', 'checkIn', 'checkOut']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const hotel: FakeHotel | null = world.findHotel(text(args, 'hotelId'));
      if (hotel === null) {
        return error('LAB_HOTEL_NOT_FOUND', 'The requested fake hotel does not exist.');
      }
      const output: LabHotelDetailOutput = {
        hotelId: hotel.hotelId,
        hotelName: hotel.name,
        roomId: hotel.roomId,
        price: hotel.price,
        currency: hotel.currency,
        checkIn: text(args, 'checkIn'),
        checkOut: text(args, 'checkOut')
      };
      return success(output);
    })
  };
}

function hotelBookingPrepareDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_HOTEL_BOOKING_PREPARE,
    revision: '1',
    name: '准备酒店预订',
    description: 'Creates a fake booking preview without confirming it. Returns bookingToken for lab.hotel.booking.confirm.',
    riskLevel: 'draft',
    inputSchema: objectSchema('Fake booking preparation request.', [
      schemaProperty('hotelId', stringSchema('Hotel id returned by lab.hotel.detail.')),
      schemaProperty('roomId', stringSchema('Room id returned by lab.hotel.detail.')),
      schemaProperty('checkIn', stringSchema('Check-in date.')),
      schemaProperty('checkOut', stringSchema('Check-out date.'))
    ], ['hotelId', 'roomId', 'checkIn', 'checkOut']),
    outputSchema: objectSchema('Prepared fake booking.', [
      schemaProperty('bookingToken', stringSchema('Token accepted by lab.hotel.booking.confirm.')),
      schemaProperty('summary', stringSchema('Human-readable booking summary.')),
      schemaProperty('price', numberSchema('Nightly fake room price.', 0)),
      schemaProperty('currency', stringSchema('Price currency.')),
      schemaProperty('status', enumStringSchema('Preparation status.', ['ready']))
    ], ['bookingToken', 'summary', 'price', 'currency', 'status']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const booking: FakePreparedBooking | null = world.prepareBooking(
        text(args, 'hotelId'),
        text(args, 'roomId'),
        text(args, 'checkIn'),
        text(args, 'checkOut')
      );
      if (booking === null) {
        return error('LAB_BOOKING_INPUT_INVALID', 'The fake hotel or room does not exist.');
      }
      const output: LabHotelBookingPrepareOutput = {
        bookingToken: booking.bookingToken,
        summary: booking.summary,
        price: booking.price,
        currency: booking.currency,
        status: 'ready'
      };
      return success(output);
    })
  };
}

function hotelBookingConfirmDefinition(world: FakeWorldState): ExperimentalToolDefinition {
  return {
    toolId: LAB_HOTEL_BOOKING_CONFIRM,
    revision: '1',
    name: '确认酒店预订',
    description: 'Confirms a booking previously prepared by lab.hotel.booking.prepare. It writes to isolated fake booking state and requires bookingToken.',
    riskLevel: 'confirm_required',
    inputSchema: objectSchema('Fake booking confirmation request.', [
      schemaProperty('bookingToken', stringSchema('Token returned by lab.hotel.booking.prepare.'))
    ], ['bookingToken']),
    outputSchema: objectSchema('Confirmed fake booking.', [
      schemaProperty('bookingId', stringSchema('Stable fake booking identifier.')),
      schemaProperty('bookingToken', stringSchema('Source preparation token.')),
      schemaProperty('summary', stringSchema('Confirmed booking summary.')),
      schemaProperty('status', enumStringSchema('Confirmation status.', ['confirmed']))
    ], ['bookingId', 'bookingToken', 'summary', 'status']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const booking: FakeConfirmedBooking | null =
        world.confirmBooking(text(args, 'bookingToken'));
      return booking === null ?
        error('LAB_BOOKING_TOKEN_NOT_FOUND', 'The fake booking token does not exist.') :
        success(booking);
    })
  };
}

function tokenIssueDefinition(): ExperimentalToolDefinition {
  return {
    toolId: LAB_TOKEN_ISSUE,
    revision: '1',
    name: '生成测试令牌',
    description: 'Produces a deterministic token from seed. This minimal tool exists to test output-to-input plan bindings.',
    riskLevel: 'read',
    inputSchema: objectSchema('Token issue request.', [
      schemaProperty('seed', stringSchema('Seed embedded in the deterministic token.'))
    ], ['seed']),
    outputSchema: objectSchema('Issued token.', [
      schemaProperty('token', stringSchema('Token accepted by lab.token.consume.'))
    ], ['token']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const output: LabTokenIssueOutput = {
        token: `token:${text(args, 'seed')}`
      };
      return success(output);
    })
  };
}

function tokenConsumeDefinition(): ExperimentalToolDefinition {
  return {
    toolId: LAB_TOKEN_CONSUME,
    revision: '1',
    name: '消费测试令牌',
    description: 'Consumes a token returned by lab.token.issue and echoes the authorization for binding verification.',
    riskLevel: 'read',
    inputSchema: objectSchema('Token consumption request.', [
      schemaProperty('authorization', stringSchema('Token returned by lab.token.issue.'))
    ], ['authorization']),
    outputSchema: objectSchema('Consumed token result.', [
      schemaProperty('authorization', stringSchema('Consumed token.')),
      schemaProperty('consumed', booleanSchema('True after successful deterministic consumption.'))
    ], ['authorization', 'consumed']),
    executor: new FunctionExperimentalToolExecutor(async (
      args: Object,
      _context: ExperimentalToolExecutionContext
    ): Promise<ExperimentalToolExecutionResult> => {
      const authorization = text(args, 'authorization');
      if (authorization.indexOf('token:') !== 0) {
        return error('LAB_TOKEN_INVALID', 'Authorization is not a fake issued token.');
      }
      const output: LabTokenConsumeOutput = {
        authorization,
        consumed: true
      };
      return success(output);
    })
  };
}

export function registerExperimentalFakeTools(
  registry: ExperimentalToolRegistry,
  world: FakeWorldState
): void {
  registry.register(dateResolveDefinition());
  registry.register(contactLookupDefinition(world));
  registry.register(emailComposeDefinition(world));
  registry.register(emailSendDefinition(world));
  registry.register(hotelSearchDefinition(world));
  registry.register(hotelDetailDefinition(world));
  registry.register(hotelBookingPrepareDefinition(world));
  registry.register(hotelBookingConfirmDefinition(world));
  registry.register(tokenIssueDefinition());
  registry.register(tokenConsumeDefinition());
}

export function createExperimentalFakeToolRegistry(
  world: FakeWorldState = new FakeWorldState()
): ExperimentalToolRegistry {
  const registry = new ExperimentalToolRegistry();
  registerExperimentalFakeTools(registry, world);
  return registry;
}
