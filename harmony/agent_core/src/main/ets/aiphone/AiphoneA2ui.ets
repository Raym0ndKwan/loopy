import { A2UI_VERSION } from '../a2ui/A2uiProtocol';

interface AiphoneCreateSurfaceBody {
  surfaceId: string;
  status: string;
  title: string;
}

interface AiphoneCreateSurfaceEnvelope {
  version: string;
  createSurface: AiphoneCreateSurfaceBody;
}

interface AiphoneRow {
  label: string;
  value: string;
}

interface AiphoneUpdateDataModelBody {
  surfaceId: string;
  path: string;
  value: AiphoneRow[];
}

interface AiphoneUpdateDataModelEnvelope {
  version: string;
  updateDataModel: AiphoneUpdateDataModelBody;
}

export function aiphoneErrorJsonl(surfaceId: string, title: string, body: string): string {
  const create: AiphoneCreateSurfaceEnvelope = {
    version: A2UI_VERSION,
    createSurface: {
      surfaceId: surfaceId,
      status: 'error',
      title: title
    }
  };
  const rows: AiphoneUpdateDataModelEnvelope = {
    version: A2UI_VERSION,
    updateDataModel: {
      surfaceId: surfaceId,
      path: '/rows',
      value: [
        { label: '错误', value: body }
      ]
    }
  };
  return JSON.stringify(create) + '\n' + JSON.stringify(rows) + '\n';
}

export function splitJsonl(jsonl: string): string[] {
  return jsonl.split(/\r?\n/).map((line: string) => line.trim()).filter((line: string) => line.length > 0);
}
