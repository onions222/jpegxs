cd('/Users/silas/Desktop/code/VideoCompress/jpegxs/matlab');
addpath(genpath(cd));
import jxs.*;

% Create test config and image
im = jxs.internal.image();
im.ncomps = int32(3); im.width = int32(64); im.height = int32(64); im.depth = int32(10);
im.sx(1:3) = int32([1 1 1]); im.sy(1:3) = int32([1 1 1]);
im.allocate(true);
for c = 1:im.ncomps, im.comps_array{c}(:) = int32(512); end

cfg = jxs.internal.xs_config.default_config();
[~, cfg] = jxs.internal.xs_config.resolve_auto_values(cfg, im);

ids_obj = jxs.internal.ids();
ids_obj.construct(im, cfg.p.NLx, cfg.p.NLy, cfg.p.Sd, cfg.p.Cw, cfg.p.Lh);
fprintf('IDs: nbands=%d, npi=%d, npx=%d\n', ids_obj.nbands, ids_obj.npi, ids_obj.npx);

% Open rate control
rc = jxs.internal.rate_control();
rc.open(cfg, ids_obj, 0);
fprintf('PBT: position_count=%d, method_count=%d\n', rc.pbt.position_count, rc.pbt.method_count);
fprintf('PBT sigf cells: %d\n', length(rc.pbt.sigf_budget_table));

% Check GCLI_METHODS_NB
fprintf('GCLI_METHODS_NB = %d (type %s)\n', Constants.GCLI_METHODS_NB, class(Constants.GCLI_METHODS_NB));
fprintf('npi = %d (type %s)\n', ids_obj.npi, class(ids_obj.npi));
fprintf('total = %d\n', int32(Constants.GCLI_METHODS_NB) * ids_obj.npi);
