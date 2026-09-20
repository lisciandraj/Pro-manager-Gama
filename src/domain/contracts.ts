import type {Database,Json} from '../data/database.types';
export type Row<T extends keyof Database['public']['Tables']> = Database['public']['Tables'][T]['Row'];
export type UUID = string;
export interface PageRequest {page:number;pageSize:number;search?:string;sort?:string;ascending?:boolean;archived?:boolean}
export interface PageResult<T> {items:T[];total:number;page:number;pageSize:number;sort?:string}
export interface Party {id:UUID;name:string;taxId:string;address:string;email:string;phone:string;city:string;active:boolean}
export interface Supplier extends Party {contactName:string;province:string;postalCode:string;country:string;notes:string}
export interface Customer extends Party {category:'A'|'B'|'C';paymentTermsDays:number|null;province:string;notes:string}
export interface Product {id:UUID;name:string;reference:string;barcode:string;category:string;supplierId:UUID|null;minStock:number;maxStock:number;stock:number;salePrice:number;salePriceB:number;purchasePrice:number;taxRate:number;active:boolean;hasPhoto:boolean}
export interface DocumentLine {product_id:UUID;quantity:number;unit_price:number;tax_rate:number}
export interface Command<T> {requestKey:UUID;expectedVersion?:number;data:T}
export interface LegacyQuoteCommand {customer_id:UUID;request_key:UUID;lines:DocumentLine[];notes?:string;details?:Record<string,Json>}
export interface PaymentCommand {invoice_id:UUID;request_key:UUID;amount:number;paid_at:string;method:'transfer'|'cash'|'card'|'check'|'other';reference?:string;account?:string;notes?:string}
export interface ProjectItemCommand {project_id:UUID;id?:UUID;kind:string;title:string;version?:number;request_key:UUID;data?:Record<string,Json>}
export interface AppError {code:string;message:string;fields:Record<string,string>;retryable:boolean}
export type RpcName = keyof Database['public']['Functions'];
export type RpcArgs<K extends RpcName> = Database['public']['Functions'][K]['Args'];
export type RpcResult<K extends RpcName> = Database['public']['Functions'][K]['Returns'];
export type ReadSchema<T extends keyof Database['public']['Tables']> = {table:T;columns:readonly (keyof Row<T>)[]};
export const directories = {
 suppliers:{table:'suppliers',columns:['id','name','tax_id','contact_name','email','active']},
 customers:{table:'customers',columns:['id','name','identification','payment_terms_days','active']},
 products:{table:'products',columns:['id','name','reference','sale_price','min_stock','has_photo','active']}
} as const satisfies {suppliers:ReadSchema<'suppliers'>;customers:ReadSchema<'customers'>;products:ReadSchema<'products'>};
