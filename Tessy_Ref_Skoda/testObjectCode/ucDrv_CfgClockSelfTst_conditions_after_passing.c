/*
 * ================================================================================
 * TESSY INTERFACE INFORMATION - ucDrv_CfgClockSelfTst
 * Generated: 2026-07-13 10:10:35
 * ================================================================================
 * 
 * EXTERNAL FUNCTIONS:
 * -------------------
 * void ucDrv_UnlockRegister()
 * void ucDrv_ConfigureFCC(const ucDrv_Cfg_ClkSelfTst_t *)
 * void ucDrv_SetFCCPeriod(const ucDrv_Cfg_ClkSelfTst_t *)
 * void ucDrv_StartFCC()
 * boolean_t ucDrv_FCCDone()
 * u32 ucDrv_ReadFCC()
 * 
 * LOCAL FUNCTIONS:
 * ----------------
 * 
 * 
 * EXTERNAL VARIABLES:
 * -------------------
 * 
 * 
 * GLOBAL VARIABLES:
 * -----------------
 * ucDrv_Cfg_ClkSelfTst_t * config_ptr [Passing: IN]
 *     u8 fccCountingPeriods_u8 [Passing: IN]
 *     ucDrv_Cfg_SYSCTL_FCC_Measure_Freq_Src_t expectedFrequency_en [Passing: IN]
 *     u8 tolerance_u8 [Passing: IN]
 *     u32 testTimeOut [Passing: IN]
 * ucDrv_ClkSelfTst_sts_t [Passing: OUT]
 * 
 * PARAMETERS:
 * -----------
 *  [Passing: ]
 * 
 * RETURN TYPE:
 * ------------
 * 
 * ================================================================================
 * 
 */

#define UCDRV_CFG_SYSCTL_FCC_TRIGSRC_FREQ_REF (32768u)
#define MSP_SL_RESULT_PASS  267448560
#define MSP_SL_RESULT_FAIL  2058005162
#define MSP_SL_RESULT_ERROR  1431655765


typedef struct
{
    ucDrv_Cfg_SYSCTL_FCC_Trigger_Level_t fccTriggerLevel_en;
    ucDrv_Cfg_SYSCTL_FCC_Trigger_Source_t fccTriggerSource_en;
    ucDrv_Cfg_SYSCTL_FCC_Measure_Source_t fccMeasureSource_en;
    u8 fccCountingPeriods_u8;
    ucDrv_Cfg_SYSCTL_FCC_Measure_Freq_Src_t expectedFrequency_en;
    u8 tolerance_u8;
    u32 testTimeOut;
} ucDrv_Cfg_ClkSelfTst_t;

typedef enum
{
    ucDrv_ClkSelfTst_Pass = 0u, 
    ucDrv_ClkSelfTst_OvFrq,	   
    ucDrv_ClkSelfTst_UnderFrq,	   
} ucDrv_ClkSelfTst_sts_t;


ucDrv_ClkSelfTst_sts_t ucDrv_CfgClockSelfTst(const ucDrv_Cfg_ClkSelfTst_t * config_ptr)
{
u32 ucDrv_Cfg_FccFrequency_u32 = 0u;
    u32 ucDrv_Cfg_FccFreqTempUp_u32 = 0u;
    u32 ucDrv_Cfg_FccFreqTempDown_u32 = 0u;
    while ((ucDrv_FCCDone() == FALSE)&&(l_Timeout_u32 > 0u))
    {
    }
    ucDrv_Cfg_FccFrequency_u32 = (ucDrv_Cfg_FccCount_u32 * UCDRV_CFG_SYSCTL_FCC_TRIGSRC_FREQ_REF) / (config_ptr->fccCountingPeriods_u8 + 1u);  
    ucDrv_Cfg_FccFreqTempUp_u32 = config_ptr->expectedFrequency_en + ((config_ptr->expectedFrequency_en * config_ptr->tolerance_u8) / 100u);
    ucDrv_Cfg_FccFreqTempDown_u32 = config_ptr->expectedFrequency_en - ((config_ptr->expectedFrequency_en * config_ptr->tolerance_u8) / 100u);
    if (ucDrv_Cfg_FccFrequency_u32 > ucDrv_Cfg_FccFreqTempUp_u32)
    {
    }
    else if (ucDrv_Cfg_FccFrequency_u32 < ucDrv_Cfg_FccFreqTempDown_u32)
    {
    }
    else
    {
    }
}