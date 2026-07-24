import {
  cloneExperimentalFrozenActionPlan,
  ExperimentalFrozenActionPlan
} from './ExperimentalFrozenActionPlan';

export interface ExperimentalFrozenActionPlanStoreResult {
  ok: boolean;
  errorCode: string;
  message: string;
}

function storeResult(
  ok: boolean,
  errorCode: string = '',
  message: string = ''
): ExperimentalFrozenActionPlanStoreResult {
  return {
    ok,
    errorCode,
    message
  };
}

export class ExperimentalFrozenActionPlanStore {
  private readonly capacity: number;
  private readonly plans: Map<string, ExperimentalFrozenActionPlan> =
    new Map<string, ExperimentalFrozenActionPlan>();

  constructor(capacity: number = 128) {
    this.capacity = capacity;
  }

  save(
    conversationId: string,
    turnId: string,
    plan: ExperimentalFrozenActionPlan
  ): ExperimentalFrozenActionPlanStoreResult {
    const key = this.key(conversationId, turnId, plan.actionTaskId);
    if (this.plans.has(key)) {
      return storeResult(
        false,
        'ACTION_PLAN_ALREADY_FROZEN',
        'An Action plan is already frozen for this actionTaskId.'
      );
    }
    if (this.plans.size >= this.capacity) {
      return storeResult(
        false,
        'ACTION_PLAN_STORE_CAPACITY',
        'Experimental frozen Action plan capacity is exhausted.'
      );
    }
    const cloned = cloneExperimentalFrozenActionPlan(plan);
    if (cloned === null) {
      return storeResult(
        false,
        'ACTION_PLAN_STORE_VALUE_INVALID',
        'Frozen Action plan could not be copied safely.'
      );
    }
    this.plans.set(key, cloned);
    return storeResult(true);
  }

  has(conversationId: string, turnId: string, actionTaskId: string): boolean {
    return this.plans.has(this.key(conversationId, turnId, actionTaskId));
  }

  find(
    conversationId: string,
    turnId: string,
    actionTaskId: string
  ): ExperimentalFrozenActionPlan | null {
    const plan = this.plans.get(this.key(conversationId, turnId, actionTaskId));
    return plan === undefined ? null : cloneExperimentalFrozenActionPlan(plan);
  }

  removeTurn(conversationId: string, turnId: string): void {
    const prefix = this.turnPrefix(conversationId, turnId);
    const keys: string[] = [];
    this.plans.forEach((_plan: ExperimentalFrozenActionPlan, key: string) => {
      if (key.startsWith(prefix)) {
        keys.push(key);
      }
    });
    for (let index = 0; index < keys.length; index++) {
      this.plans.delete(keys[index]);
    }
  }

  clear(): void {
    this.plans.clear();
  }

  size(): number {
    return this.plans.size;
  }

  private key(
    conversationId: string,
    turnId: string,
    actionTaskId: string
  ): string {
    return `${this.turnPrefix(conversationId, turnId)}` +
      `${actionTaskId.length}:${actionTaskId}`;
  }

  private turnPrefix(conversationId: string, turnId: string): string {
    return `${conversationId.length}:${conversationId}` +
      `${turnId.length}:${turnId}`;
  }
}
